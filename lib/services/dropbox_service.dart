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
    final bytes = await File(localPath).readAsBytes();
    await uploadBytes(bytes, dropboxPath);
  }

  /// Uploads raw [bytes] (a generated JSON report, a photo already held in
  /// memory, a rendered PDF, ...) directly to `dropboxPath`, without needing
  /// a real local file first — the norm now that Dropbox itself is the
  /// primary data store rather than just a backup target.
  Future<void> uploadBytes(Uint8List bytes, String dropboxPath) async {
    final accessToken = await _getAccessToken();

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

  /// Convenience wrapper for [uploadBytes] with a UTF-8 JSON string.
  Future<void> uploadJson(Map<String, dynamic> json, String dropboxPath) =>
      uploadBytes(utf8.encode(jsonEncode(json)), dropboxPath);

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

  /// Downloads and JSON-decodes a file previously written by [uploadJson].
  Future<Map<String, dynamic>> downloadJson(String dropboxPath) async {
    final bytes = await downloadFile(dropboxPath);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final accessToken = await _getAccessToken();
    final response = await http.post(
      Uri.https('api.dropboxapi.com', endpoint),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw StateError('Dropbox API $endpoint 失敗：${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Creates a folder at [path] (e.g. `/工地A`). No-ops (via Dropbox's own
  /// `path/conflict` error) if it already exists.
  Future<void> createFolder(String path) async {
    try {
      await _post('/2/files/create_folder_v2', {
        'path': path,
        'autorename': false,
      });
    } catch (e) {
      if (e.toString().contains('path/conflict')) return;
      rethrow;
    }
  }

  /// Lists immediate entries (files and folders) under [path].
  Future<List<Map<String, dynamic>>> listFolder(String path) async {
    final result = await _post('/2/files/list_folder', {
      'path': path,
      'recursive': false,
    });
    var entries = List<Map<String, dynamic>>.from(
      result['entries'] as List,
    );
    var hasMore = result['has_more'] as bool? ?? false;
    var cursor = result['cursor'] as String?;
    while (hasMore && cursor != null) {
      final next = await _post('/2/files/list_folder/continue', {
        'cursor': cursor,
      });
      entries.addAll(List<Map<String, dynamic>>.from(next['entries'] as List));
      hasMore = next['has_more'] as bool? ?? false;
      cursor = next['cursor'] as String?;
    }
    return entries;
  }

  /// Converts [path] into a Dropbox shared folder and returns its
  /// `shared_folder_id`. Safe to call again on an already-shared folder —
  /// Dropbox returns a `shared_folder_already_exists` error in that case,
  /// which is treated as success by looking the id up via [listFolder]'s
  /// metadata instead.
  Future<String> shareFolder(String path) async {
    try {
      final result = await _post('/2/sharing/share_folder', {'path': path});
      return result['shared_folder_id'] as String;
    } catch (e) {
      if (e.toString().contains('already_shared')) {
        final meta = await _post('/2/files/get_metadata', {'path': path});
        final sharedInfo = meta['shared_folder_id'];
        if (sharedInfo != null) return sharedInfo as String;
      }
      rethrow;
    }
  }

  /// Invites [memberEmail] (the company/admin's Dropbox account) to a
  /// shared folder with read-only access.
  Future<void> addFolderMember(
    String sharedFolderId,
    String memberEmail,
  ) async {
    await _post('/2/sharing/add_folder_member', {
      'shared_folder_id': sharedFolderId,
      'members': [
        {
          'member': {'.tag': 'email', 'email': memberEmail},
          'access_level': {'.tag': 'viewer'},
        },
      ],
      'quiet': false,
    });
  }

  /// Lists every shared folder the *currently linked* account can see —
  /// used by the admin view to enumerate all 工地 folders that report-writers
  /// have shared with it.
  Future<List<Map<String, dynamic>>> listSharedFolders() async {
    final result = await _post('/2/sharing/list_folders', {'limit': 100});
    var entries = List<Map<String, dynamic>>.from(
      result['entries'] as List,
    );
    var cursor = result['cursor'] as String?;
    while (cursor != null) {
      final next = await _post('/2/sharing/list_folders/continue', {
        'cursor': cursor,
      });
      final nextEntries = List<Map<String, dynamic>>.from(
        next['entries'] as List,
      );
      if (nextEntries.isEmpty) break;
      entries.addAll(nextEntries);
      cursor = next['cursor'] as String?;
    }
    return entries;
  }

  /// Server-side copy of an entire folder (e.g. a shared 工地 folder) into
  /// [toPath] in the *same* linked account — no bytes pass through the
  /// client. Used by the admin view's auto-backup-on-login. `autorename:
  /// true` so a stale destination from a previous run doesn't block the copy.
  Future<void> copyFolder(String fromPath, String toPath) async {
    await _post('/2/files/copy_v2', {
      'from_path': fromPath,
      'to_path': toPath,
      'autorename': true,
    });
  }
}
