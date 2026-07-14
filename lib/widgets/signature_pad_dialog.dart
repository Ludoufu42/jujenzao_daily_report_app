import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../theme.dart';

/// Generic signature-capture dialog, reused for both the daily report's
/// 工地主任 signature and the 要徑查驗 inspector's signature.
Future<Uint8List?> showSignatureDialog(
  BuildContext context, {
  required String title,
}) async {
  final controller = SignatureController(
    penStrokeWidth: 3,
    penColor: AppColors.textPrimary,
    exportBackgroundColor: Colors.white,
  );

  final result = await showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 400,
        height: 220,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Signature(
                  controller: controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.clear,
                child: const Text('清除重簽'),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: '取消',
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  if (controller.isEmpty) return;
                  final bytes = await controller.toPngBytes();
                  if (context.mounted) Navigator.of(context).pop(bytes);
                },
                child: const Text('確認簽名'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  controller.dispose();
  return result;
}

/// Backwards-compatible wrapper for the daily report's 工地主任 signature.
Future<Uint8List?> showSupervisorSignatureDialog(BuildContext context) =>
    showSignatureDialog(context, title: '工地主任簽名');
