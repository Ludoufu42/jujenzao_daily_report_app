import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'auth_user.dart';
import 'cloud_config.dart';

@JS('jzGoogle.ready')
external bool _ready();

@JS('jzGoogle.init')
external bool _init(String clientId, JSFunction callback);

@JS('jzGoogle.saved')
external String _saved();

@JS('jzGoogle.prompt')
external void _prompt();

@JS('jzGoogle.makeButton')
external JSObject _makeButton();

@JS('jzGoogle.signOut')
external void _signOut();

@JS('jzGoogle.inAppBrowser')
external String _inAppBrowser();

/// 在 LINE、Facebook 等 App 內建瀏覽器裡開啟時回傳它的名稱,否則 null。
/// Google 不允許在內建瀏覽器登入,畫面要請使用者改用 Safari / Chrome。
String? inAppBrowserName() {
  try {
    final name = _inAppBrowser();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}

/// 網頁版 Google 登入(Google Identity Services)。登入結果是 ID token,
/// 之後每次呼叫 Worker 都帶它;token 約一小時到期,到期時先試著靜默更新。
class GoogleAuth {
  GoogleAuth._();
  static final GoogleAuth instance = GoogleAuth._();

  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);
  bool _initialized = false;
  Completer<void>? _refreshing;

  Future<void> init() async {
    if (_initialized) return;
    // GIS 的 script 是非同步載入,最多等 10 秒。
    for (var i = 0; i < 50 && !_isReady(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!_isReady()) return;
    if (!_init(CloudConfig.googleClientId, _onCredential.toJS)) return;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _makeButton(),
    );
    _initialized = true;
    final saved = _saved();
    if (saved.isNotEmpty) _onCredential(saved);
  }

  static const _viewType = 'jz-google-sign-in-button';

  bool _isReady() {
    try {
      return _ready();
    } catch (_) {
      return false;
    }
  }

  void _onCredential(String token) {
    final u = AuthUser.fromIdToken(token);
    if (u == null) return;
    user.value = u;
    _refreshing?.complete();
  }

  /// 目前有效的 ID token;快過期就試著靜默換一張,換不到回傳 null。
  Future<String?> getIdToken() async {
    final u = user.value;
    if (u != null && u.isFresh) return u.idToken;
    if (!_initialized) return null;
    final pending = _refreshing = Completer<void>();
    _prompt();
    try {
      await pending.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // 沒換到:需要重新按登入鈕。
    }
    _refreshing = null;
    final fresh = user.value;
    if (fresh != null && fresh.isFresh) return fresh.idToken;
    return null;
  }

  void signOut() {
    _signOut();
    user.value = null;
  }
}

Widget buildGoogleSignInButton() => const SizedBox(
  width: 300,
  height: 48,
  child: HtmlElementView(viewType: GoogleAuth._viewType),
);
