import 'dart:convert';

/// Google 登入後的使用者與 ID token。token 只在客戶端解開來取 email、姓名、
/// 到期時間(顯示用);真正的驗證(簽章、aud、名單)一律在 Worker 做。
class AuthUser {
  final String email;
  final String name;
  final String idToken;
  final DateTime expiresAt;

  const AuthUser({
    required this.email,
    required this.name,
    required this.idToken,
    required this.expiresAt,
  });

  /// 到期前一分鐘就視為過期,避免送出時剛好失效。
  bool get isFresh =>
      expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  static AuthUser? fromIdToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
              as Map<String, dynamic>;
      final email = payload['email'] as String?;
      final exp = payload['exp'];
      if (email == null || exp is! num) return null;
      return AuthUser(
        email: email.toLowerCase(),
        name: payload['name'] as String? ?? '',
        idToken: token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000),
      );
    } catch (_) {
      return null;
    }
  }
}
