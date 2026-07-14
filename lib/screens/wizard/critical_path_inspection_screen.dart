import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:universal_io/io.dart';

import '../../db/report_repository.dart';
import '../../models/inspection.dart';
import '../../models/inspection_checklist.dart';
import '../../models/project.dart';
import '../../services/dropbox_service.dart';
import '../../services/inspection_pdf_service.dart';
import '../../services/photo_import_service.dart';
import '../../services/web_blob_store.dart';
import '../../theme.dart';
import '../../widgets/photo_path_image.dart';
import '../../widgets/signature_pad_dialog.dart';

class CriticalPathInspectionScreen extends StatefulWidget {
  final Project project;
  final String criticalPathLabel;
  final String workItemName;

  const CriticalPathInspectionScreen({
    super.key,
    required this.project,
    required this.criticalPathLabel,
    required this.workItemName,
  });

  @override
  State<CriticalPathInspectionScreen> createState() =>
      _CriticalPathInspectionScreenState();
}

class _CriticalPathInspectionScreenState
    extends State<CriticalPathInspectionScreen> {
  final _repo = ReportRepository.instance;
  final _picker = ImagePicker();
  final _importer = PhotoImportService.instance;

  late final InspectionChecklistTemplate? _template;
  final Map<String, InspectionResult?> _results = {};
  final List<String> _photoPaths = [];
  Uint8List? _signature;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _template = templateForWorkItem(widget.workItemName);
    if (_template != null) {
      for (final item in _template.items) {
        _results[item.name] = null;
      }
    }
  }

  Future<void> _addPhotos({required bool fromCamera}) async {
    setState(() => _busy = true);
    try {
      if (fromCamera) {
        final photo = await _picker.pickImage(source: ImageSource.camera);
        if (photo == null) return;
        _photoPaths.addAll(await _importer.importPhotos([photo]));
      } else {
        final photos = await _picker.pickMultiImage();
        if (photos.isEmpty) return;
        _photoPaths.addAll(await _importer.importPhotos(photos));
      }
      setState(() {});
    } on PhotoImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sign() async {
    final bytes = await showSignatureDialog(context, title: '查驗人員簽名');
    if (bytes == null) return;
    setState(() => _signature = bytes);
  }

  bool get _allItemsAnswered =>
      _template != null && _results.values.every((r) => r != null);

  Future<void> _submit() async {
    if (_template == null) return;
    if (!_allItemsAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請完成所有檢查項目的合格/缺失勾選')),
      );
      return;
    }
    if (_signature == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先完成查驗人員簽名')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final itemRecords = _template.items
          .map(
            (def) => InspectionItemRecord(
              inspectionId: 0, // filled in by repository
              itemName: def.name,
              description: def.description,
              result: _results[def.name]!,
            ),
          )
          .toList();

      final String sigPath;
      if (kIsWeb) {
        sigPath = WebBlobStore.put(_signature!, suggestedName: 'signature.png');
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final sigDir = Directory(p.join(docs.path, 'inspection_signatures'));
        if (!await sigDir.exists()) await sigDir.create(recursive: true);
        sigPath = p.join(sigDir.path, 'sig_${now.microsecondsSinceEpoch}.png');
        await File(sigPath).writeAsBytes(_signature!);
      }

      final inspectionId = await _repo.createInspection(
        inspection: Inspection(
          projectId: widget.project.id!,
          criticalPathLabel: widget.criticalPathLabel,
          templateName: _template.templateName,
          inspectorSignaturePath: sigPath,
          createdAt: now,
        ),
        items: itemRecords,
        photoPaths: _photoPaths,
      );

      final pdfBytes = await InspectionPdfService.generate(
        project: widget.project,
        criticalPathLabel: widget.criticalPathLabel,
        templateName: _template.templateName,
        items: itemRecords,
        photoPaths: _photoPaths,
        inspectorSignature: _signature!,
        inspectedAt: now,
      );

      // 檔名規則：案名+要徑名稱+日期(yyyymmdd)。若同一天對同一要徑重複查驗（例如缺失複驗），
      // 加上 (2)(3)... 避免覆蓋掉前一次查驗的 PDF。
      String sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final baseName =
          '${sanitize(widget.project.name)}${sanitize(widget.criticalPathLabel)}'
          '${DateFormat('yyyyMMdd').format(now)}';

      final String pdfPath;
      if (kIsWeb) {
        pdfPath = WebBlobStore.put(pdfBytes, suggestedName: '$baseName.pdf');
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final pdfDir = Directory(p.join(docs.path, 'inspection_pdfs'));
        if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
        var path = p.join(pdfDir.path, '$baseName.pdf');
        var suffix = 2;
        while (await File(path).exists()) {
          path = p.join(pdfDir.path, '$baseName($suffix).pdf');
          suffix++;
        }
        await File(path).writeAsBytes(pdfBytes);
        pdfPath = path;
      }
      await _repo.updateInspectionPdfPath(inspectionId, pdfPath);

      var uploadedToCloud = false;
      if (!kIsWeb) {
        try {
          if (await DropboxService.instance.isLinked()) {
            await DropboxService.instance.uploadFile(
              pdfPath,
              '/inspections/${p.basename(pdfPath)}',
            );
            uploadedToCloud = true;
          }
        } catch (_) {
          // Best-effort — the inspection record itself is already saved.
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uploadedToCloud ? '查驗紀錄已儲存並上傳 Dropbox' : '查驗紀錄已儲存（未上傳雲端）'),
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      '要徑查驗',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: cardShadow,
                ),
                child: _template == null
                    ? _buildNoTemplate()
                    : _buildForm(_template),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoTemplate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.criticalPathLabel,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Text(
          '「${widget.workItemName}」目前沒有設定查驗表，此工項不需要查驗。',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildForm(InspectionChecklistTemplate template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.criticalPathLabel,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        Text(
          '查驗表：${template.templateName}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ...template.items.map(_buildChecklistRow),
        const SizedBox(height: 16),
        const Text('現場照片', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: '拍照',
                onPressed: _busy ? null : () => _addPhotos(fromCamera: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SecondaryButton(
                label: '選取照片',
                onPressed: _busy ? null : () => _addPhotos(fromCamera: false),
              ),
            ),
          ],
        ),
        if (_photoPaths.isNotEmpty) ...[
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _photoPaths.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PhotoPathImage(_photoPaths[index], fit: BoxFit.cover),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text('查驗人員簽名', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (_signature == null)
          SecondaryButton(label: '前往簽名', onPressed: _busy ? null : _sign)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(_signature!),
              ),
              const SizedBox(height: 8),
              SecondaryButton(label: '重新簽名', onPressed: _busy ? null : _sign),
            ],
          ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: _busy ? '處理中…' : '完成查驗並產生 PDF',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }

  Widget _buildChecklistRow(ChecklistItemDef item) {
    final result = _results[item.name];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            item.description,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _resultButton(
                  label: '合格',
                  selected: result == InspectionResult.pass,
                  color: AppColors.primary,
                  onTap: () =>
                      setState(() => _results[item.name] = InspectionResult.pass),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _resultButton(
                  label: '缺失',
                  selected: result == InspectionResult.defect,
                  color: AppColors.danger,
                  onTap: () => setState(
                    () => _results[item.name] = InspectionResult.defect,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultButton({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
