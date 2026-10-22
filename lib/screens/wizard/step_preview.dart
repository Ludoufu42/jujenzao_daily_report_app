import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/weather.dart';
import '../../services/backup_service.dart';
import '../../services/pdf_service.dart';
import '../../services/report_upload.dart';
import '../../wizard/report_saver.dart';
import '../../theme.dart';
import '../../widgets/signature_pad_dialog.dart';
import '../../wizard/report_draft.dart';
import '../../wizard/report_preview_data.dart';

const _chartColors = [
  AppColors.primary,
  Color(0xFF639922),
  Color(0xFF378ADD),
  Color(0xFFBA7517),
  Color(0xFFD4537E),
];

class StepPreview extends StatefulWidget {
  final VoidCallback onBack;
  const StepPreview({super.key, required this.onBack});

  @override
  State<StepPreview> createState() => _StepPreviewState();
}

class _StepPreviewState extends State<StepPreview> {
  final _repo = ReportRepository.instance;
  Future<ReportPreviewData>? _future;
  bool _saved = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ReportPreviewData.build(context.read<ReportDraft>(), _repo);
  }

  /// 回傳要顯示給使用者的結果文字(已經存過就回傳 null)。
  Future<String?> _saveReport(ReportDraft draft) async {
    if (_saved) return null;
    await persistDraft(draft, _repo);
    _saved = true;

    // Every completed report triggers a dated local "time machine" backup.
    // Backup failure must never block the save the user actually asked for.
    try {
      await BackupService.instance.exportBackup();
    } catch (_) {
      // Swallowed deliberately: the daily report itself is already saved;
      // a failed incidental backup shouldn't surface as a save failure.
    }

    // 日報產生後自動上傳雲端(R2);失敗只提示,本機已存好。
    return uploadReportToCloud(draft, await _future!);
  }

  Future<void> _onSaveReportPressed(ReportDraft draft) async {
    setState(() => _busy = true);
    try {
      final message = await _saveReport(draft);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message ?? '已儲存日報')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onGeneratePdfPressed(
    ReportDraft draft,
    ReportPreviewData data,
  ) async {
    final signature = await showSupervisorSignatureDialog(context);
    if (signature == null) return;
    setState(() => _busy = true);
    try {
      final message = await _saveReport(draft);
      if (message != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      final bytes = await PdfService.generate(
        draft: draft,
        data: data,
        photoPaths: draft.photoPaths,
        supervisorSignature: signature,
      );
      final pdfMessage = await uploadReportPdfToCloud(draft, data, bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(pdfMessage)));
      }
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();
    final dateFormat = DateFormat('yyyy-MM-dd');

    return StepCard(
      stepNumber: 7,
      title: '日報表預覽與 PDF',
      subtitle: '確認內容後可輸出 PDF 檔。',
      child: FutureBuilder<ReportPreviewData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: '儲存日報',
                      onPressed: _busy
                          ? null
                          : () => _onSaveReportPressed(draft),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SecondaryButton(
                      label: '產生/儲存 PDF',
                      onPressed: _busy
                          ? null
                          : () => _onGeneratePdfPressed(draft, data),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: '結束填報',
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
              const SizedBox(height: 8),
              SecondaryButton(label: '上一頁', onPressed: widget.onBack),
              const SizedBox(height: 20),
              _PreviewCard(draft: draft, data: data, dateFormat: dateFormat),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final ReportDraft draft;
  final ReportPreviewData data;
  final DateFormat dateFormat;

  const _PreviewCard({
    required this.draft,
    required this.data,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final project = draft.project;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '營建工程管理日報表',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const Divider(height: 20, thickness: 2, color: AppColors.primary),
          _infoRow('專案名稱', project.name, '公司名稱', project.companyName),
          _infoRow(
            '天氣',
            '上午：${draft.weatherAm.label}',
            '',
            '下午：${draft.weatherPm.label}',
          ),
          _infoRow(
            '日期類別',
            data.weekdayLabel,
            '日報日期',
            dateFormat.format(draft.reportDate),
          ),
          _infoRow(
            '開工日期',
            dateFormat.format(project.startDate),
            '竣工日期',
            dateFormat.format(project.plannedCompletionDate),
          ),
          _infoRow(
            '日曆天數',
            '${data.calendarDays} 天',
            '剩餘天數',
            '${data.remainingDays} 天',
          ),
          if (data.workingDays != null)
            _infoRow('工作天數', '${data.workingDays} 天', '', ''),
          _infoRow('今日進度', draft.todayProgress, '', ''),
          _infoRow('明日進度', draft.tomorrowProgress, '', ''),
          _infoRow('備註', draft.notes, '', ''),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _LaborDonut(data: data)),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox(
                  '營建材料',
                  data.materialRows
                      .map(
                        (r) =>
                            '${r.tradeType.name} ${r.quantity}${r.tradeType.unit}',
                      )
                      .toList(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox(
                  '機具設備',
                  data.equipmentRows
                      .map(
                        (r) =>
                            '${r.tradeType.name} ${r.quantity}${r.tradeType.unit}',
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '人員、材料、機具進場紀錄',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _detailTable(),
          const SizedBox(height: 14),
          const Text(
            '現場照片',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          if (draft.photoPaths.isEmpty)
            const Text(
              '本日無照片。',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            Text(
              '共 ${draft.photoPaths.length} 張照片（完整照片顯示於產生的 PDF 中）',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label1, String value1, String label2, String value2) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label1,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value1, style: const TextStyle(fontSize: 12))),
          if (label2.isNotEmpty || value2.isNotEmpty) ...[
            SizedBox(
              width: 70,
              child: Text(
                label2,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: Text(value2, style: const TextStyle(fontSize: 12))),
          ],
        ],
      ),
    );
  }

  Widget _summaryBox(String title, List<String> lines) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            const Text(
              '本日無資料',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            )
          else
            Expanded(
              child: ListView(
                children: lines
                    .map((l) => Text(l, style: const TextStyle(fontSize: 11)))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailTable() {
    const headers = [
      '大項',
      '項目',
      '單位',
      '上午',
      '下午',
      '本日合計',
      '累計',
      '代工',
      '廠商',
      '今日工作內容/使用位置',
      '明日工作內容',
    ];
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    final rows = <List<String>>[];
    for (final r in data.laborRows) {
      rows.add([
        r.tradeType.category,
        r.tradeType.name,
        r.tradeType.unit,
        fmt(r.morning),
        fmt(r.afternoon),
        fmt(r.todayTotal),
        fmt(r.cumulative),
        r.isSubcontracted ? '■' : '',
        r.vendor,
        r.todayContent,
        r.tomorrowContent,
      ]);
    }
    for (final r in data.materialRows) {
      rows.add([
        r.tradeType.category,
        r.tradeType.name,
        r.tradeType.unit,
        '',
        '',
        fmt(r.quantity),
        fmt(r.cumulative),
        '',
        '',
        r.usageLocation,
        '',
      ]);
    }
    for (final r in data.equipmentRows) {
      rows.add([
        r.tradeType.category,
        r.tradeType.name,
        r.tradeType.unit,
        '',
        '',
        fmt(r.quantity),
        fmt(r.cumulative),
        r.isSubcontracted ? '■' : '',
        r.vendor,
        r.todayContent,
        r.tomorrowContent,
      ]);
    }

    if (rows.isEmpty) {
      return const Text(
        '本日無資料',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFEFECE3)),
        columns: headers
            .map(
              (h) => DataColumn(
                label: Text(h, style: const TextStyle(fontSize: 11)),
              ),
            )
            .toList(),
        rows: rows
            .map(
              (r) => DataRow(
                cells: r
                    .map(
                      (c) => DataCell(
                        Text(c, style: const TextStyle(fontSize: 11)),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LaborDonut extends StatelessWidget {
  final ReportPreviewData data;
  const _LaborDonut({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.laborByCategory.entries.toList();
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '人員',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (total <= 0)
            const Text(
              '本日無資料',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            )
          else
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 1,
                        centerSpaceRadius: 16,
                        sections: entries.asMap().entries.map((e) {
                          return PieChartSectionData(
                            value: e.value.value,
                            color: _chartColors[e.key % _chartColors.length],
                            showTitle: false,
                            radius: 14,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ListView(
                      children: entries.asMap().entries.map((e) {
                        final pct = (e.value.value / total * 100).round();
                        return Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              color: _chartColors[e.key % _chartColors.length],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${e.value.key} $pct%',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
