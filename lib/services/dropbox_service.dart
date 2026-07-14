import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:universal_io/io.dart';

import 'dropbox_config.dart';

class DropboxNotLinkedException implements Exception {
  @override
  String toString() => 'Dropbox 帳號尚未登入授權';
}

/// Thin wrapper around Dropbox's OAuth2 PKCE flow (no client secret needed)
/// and the `/2/files/upload` REST endpoint. Scope is deliberately narrow:
/// this app only ever uploads dated backup files into its own App-folder
/// sandbox, it never reads or lists the user's other Dropbox content.
class DropboxService {
  DropboxService._internal();
  static final DropboxService instance = DropboxService._internal();

  static const _storage = FlutterSecureStorage();
  static const _refreshTokenKey = 'dropbox_refresh_token';

  final _random = Random.secure();

  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      64,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  String _codeChallengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<bool> isLinked() async {
    final token = await _storage.read(key: _refreshTokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> unlink() async {
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Opens the system browser for the user to log in to Dropbox and approve
  /// "App folder" access once. Stores the long-lived refresh token afterwards.
  Future<void> linkAccount() async {
    if (!DropboxConfig.isConfigured) {
      throw StateError('尚未設定 Dropbox App Key（DropboxConfig.appKey 是空的）');
    }

    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeFor(verifier);

    final authUrl = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': DropboxConfig.appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'redirect_uri': DropboxConfig.redirectUri,
    });

    final callbackScheme = Uri.parse(DropboxConfig.redirectUri).scheme;
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: callbackScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      throw StateError('Dropbox 授權失敗：找不到 code');
    }

    final tokenResponse = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      body: {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': DropboxConfig.appKey,
        'code_verifier': verifier,
        'redirect_uri': DropboxConfig.redirectUri,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw StateError('Dropbox 換取 token 失敗：${tokenResponse.body}');
    }

    final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final refreshToken = json['refresh_token'] as String?;
    if (refreshToken == null) {
      throw StateError('Dropbox 回應中沒有 refresh_token');
    }
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String> _getAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) throw DropboxNotLinkedException();

    final response = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': DropboxConfig.appKey,
      },
    );
    if (response.statusCode != 200) {
      throw StateError('Dropbox 更新 access token 失敗：${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['access_token'] as String;
  }

  /// Uploads [localPath] to `dropboxPath` (e.g. `/backups/2026-07-11.db`),
  /// overwriting any existing file at that path.
  Future<void> uploadFile(String localPath, String dropboxPath) async {
    final accessToken = await _getAccessToken();
    final bytes = await File(localPath).readAsBytes();

    final apiArg = jsonEncode({
      'path': dropboxPath,
      'mode': 'overwrite',
      'autorename': false,
      'mute': true,
    });

    final response = await http.post(
      Uri.https('content.dropboxapi.com', '/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Dropbox-API-Arg': apiArg,
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw StateError('Dropbox 上傳失敗：${response.body}');
    }
  }

  Future<Uint8List> downloadFile(String dropboxPath) async {
    final accessToken = await _getAccessToken();
    final apiArg = jsonEncode({'path': dropboxPath});

    final response = await http.post(
      Uri.https('content.dropboxapi.com', '/2/files/download'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Dropbox-API-Arg': apiArg,
      },
    );

    if (response.statusCode != 200) {
      throw StateError('Dropbox 下載失敗：${response.body}');
    }
    return response.bodyBytes;
  }
}
