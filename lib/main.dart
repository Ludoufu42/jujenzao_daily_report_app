import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_user.dart';
import 'services/google_auth.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleAuth.instance.init();
  runApp(const JujenzaoApp());
}

class JujenzaoApp extends StatelessWidget {
  const JujenzaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '營建工程管理日報表',
      theme: buildAppTheme(),
      home: const _AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 沒登入 → 登入畫面;登入了 → 首頁。換人登入時整個首頁重建(用 email 當 key)。
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: GoogleAuth.instance.user,
      builder: (context, user, _) => user == null
          ? const LoginScreen()
          : HomeScreen(key: ValueKey(user.email), user: user),
    );
  }
}
