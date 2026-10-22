import 'package:flutter/material.dart';

import 'auth_user.dart';

/// 非網頁平台(測試、桌面)沒有 Google 登入:永遠是未登入。
class GoogleAuth {
  GoogleAuth._();
  static final GoogleAuth instance = GoogleAuth._();

  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  Future<void> init() async {}
  Future<String?> getIdToken() async => null;
  void signOut() => user.value = null;
}

String? inAppBrowserName() => null;

Widget buildGoogleSignInButton() => const Text('此平台尚未支援 Google 登入');
