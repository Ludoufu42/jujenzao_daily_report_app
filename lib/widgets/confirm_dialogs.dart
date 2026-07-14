import 'package:flutter/material.dart';

import '../theme.dart';

Future<bool> _showDialog(
  BuildContext context, {
  Widget? icon,
  required String title,
  required List<String> bullets,
  required String confirmLabel,
  Color confirmColor = AppColors.primary,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) Center(child: icon),
            if (icon != null) const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('・ '),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
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
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(confirmLabel, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> showResetStepConfirmDialog(BuildContext context) {
  return _showDialog(
    context,
    title: '確定要清空這一步驟的內容嗎？',
    bullets: const ['只會清空目前這一頁已填寫的內容，不影響其他步驟已填的資料。'],
    confirmLabel: '確定清空',
  );
}

Future<bool> showDeleteTradeTypeConfirmDialog(
  BuildContext context,
  String itemName,
) {
  return _showDialog(
    context,
    title: '確定要刪除「$itemName」嗎？',
    bullets: [
      '刪除後，「$itemName」不會再出現在之後的日報表單中，無法再輸入這個工項的資料。',
      '過去已經記錄的資料不會被刪除，歷史報表與統計仍看得到。',
      '如果只是暫時用不到、以後可能還會用，建議改用「停用」，隨時可以打開。',
    ],
    confirmLabel: '確定刪除',
  );
}

Future<bool> showForceDeleteTradeTypeConfirmDialog(
  BuildContext context,
  String itemName,
) {
  return _showDialog(
    context,
    icon: Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.dangerBg,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.warning_rounded,
        color: AppColors.danger,
        size: 30,
      ),
    ),
    title: '確定要永久刪除「$itemName」嗎？此動作無法復原！',
    bullets: [
      '「$itemName」以及它過去所有輸入過的資料（每天的人數、廠商、工作內容、累計數字）都會被永久刪除，就像從來沒有記錄過一樣。',
      '之後所有報表、統計、匯出的 Excel 都不會再看到「$itemName」的任何蹤跡。',
      '如果只是想讓它以後不要出現、但保留過去記錄，請改用「刪除」而不是「強制刪除」。',
    ],
    confirmLabel: '我了解後果\n永久刪除',
    confirmColor: AppColors.danger,
  );
}

Future<bool> showRestoreBackupConfirmDialog(BuildContext context) {
  return _showDialog(
    context,
    icon: Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.dangerBg,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.warning_rounded,
        color: AppColors.danger,
        size: 30,
      ),
    ),
    title: '確定要匯入這份備份嗎？此動作無法復原！',
    bullets: const [
      '匯入後，會完全覆蓋掉現在本機所有資料（包含之後才新增的專案/日報），回到這份備份當時的狀態。',
      '這會覆蓋掉現在所有資料，此動作無法復原，請先確認真的要回到這個時間點。',
    ],
    confirmLabel: '我了解後果\n確定匯入並覆蓋',
    confirmColor: AppColors.danger,
  );
}
