import 'package:flutter/material.dart';

import '../services/google_auth.dart';
import '../theme.dart';

/// 未登入時的畫面:只有 Google 登入鈕。誰能進去由雲端的名單決定。
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
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
