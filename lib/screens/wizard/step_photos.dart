import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/photo_import_service.dart';
import '../../theme.dart';
import '../../widgets/photo_path_image.dart';
import '../../wizard/report_draft.dart';

class StepPhotos extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepPhotos({super.key, required this.onNext, required this.onBack});

  @override
  State<StepPhotos> createState() => _StepPhotosState();
}

class _StepPhotosState extends State<StepPhotos> {
  final _picker = ImagePicker();
  final _importer = PhotoImportService.instance;
  bool _importing = false;

  Future<void> _takePhoto(ReportDraft draft) async {
    final photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;
    await _importAndAdd(draft, [photo]);
  }

  Future<void> _pickFromGallery(ReportDraft draft) async {
    final photos = await _picker.pickMultiImage();
    if (photos.isEmpty) return;
    await _importAndAdd(draft, photos);
  }

  Future<void> _importAndAdd(ReportDraft draft, List<XFile> files) async {
    setState(() => _importing = true);
    try {
      final paths = await _importer.importPhotos(files);
      draft.photoPaths.addAll(paths);
      draft.touch();
    } on PhotoImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();

    return StepCard(
      stepNumber: 6,
      title: '現場照片',
      subtitle: '可直接使用平板相機拍照，照片會顯示於日報表。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashedActionBox(
            icon: Icons.add,
            label: '拍照',
            onTap: _importing ? null : () => _takePhoto(draft),
          ),
          const SizedBox(height: 12),
          _DashedActionBox(
            icon: Icons.grid_view_rounded,
            label: '選取照片',
            onTap: _importing ? null : () => _pickFromGallery(draft),
          ),
          if (_importing) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('處理照片中（若為 HEIC 會自動轉檔）…',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (draft.photoPaths.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '尚未加入照片。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: draft.photoPaths.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (context, index) {
                final path = draft.photoPaths[index];
                return Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PhotoPathImage(
                          path,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          draft.photoPaths.removeAt(index);
                          draft.touch();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dangerBg,
                          foregroundColor: AppColors.danger,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('移除'),
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 20),
          SecondaryButton(label: '上一頁', onPressed: widget.onBack),
          const SizedBox(height: 8),
          PrimaryButton(label: '完成', onPressed: widget.onNext),
        ],
      ),
    );
  }
}

class _DashedActionBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _DashedActionBox({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
