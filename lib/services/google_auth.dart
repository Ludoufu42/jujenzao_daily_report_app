// 網頁版用 Google Identity Services;其他平台(測試、桌面)用不登入的替身。
export 'google_auth_stub.dart'
    if (dart.library.js_interop) 'google_auth_web.dart';
