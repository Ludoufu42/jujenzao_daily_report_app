import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/google_auth.dart';
import '../theme.dart';

/// 未登入時的畫面:只有 Google 登入鈕。誰能進去由雲端的名單決定。
/// 在 LINE、Facebook 等內建瀏覽器裡 Google 不給登入(登入頁會一片空白),
/// 所以偵測到時先提醒改用 Safari / Chrome 開啟,並提供複製網址。
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inApp = inAppBrowserName();
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '營建工程管理日報表',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '請用 Google 帳號登入。\n只有管理者加入名單的帳號才能使用。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (inApp != null) ...[
                  const SizedBox(height: 20),
                  _InAppBrowserWarning(browserName: inApp),
                ],
                const SizedBox(height: 24),
                buildGoogleSignInButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InAppBrowserWarning extends StatelessWidget {
  final String browserName;
  const _InAppBrowserWarning({required this.browserName});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        border: Border.all(color: AppColors.danger),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '你現在是在「$browserName」內開啟，Google 不允許在這裡登入。',
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '請改用 Safari（iPhone）或 Chrome（Android）開啟：\n'
            '1. 按「複製網址」\n'
            '2. 打開 Safari 或 Chrome，貼到網址列前往\n'
            '登入後再「加到主畫面」，之後就不用再從 LINE 點。',
            style: TextStyle(color: AppColors.danger, fontSize: 13),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: Uri.base.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已複製網址，請貼到 Safari 或 Chrome')),
                );
              }
            },
            child: const Text('複製網址'),
          ),
        ],
      ),
    );
  }
}
