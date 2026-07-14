import 'dart:convert';
import 'dart:typed_data';

import '../services/dropbox_service.dart';

/// Minimal file-access contract that [DropboxReportRepository] depends on,
/// so its business logic (cumulative calc, backfill recompute, folder
/// layout) can be unit tested against [InMemoryProjectFileStore] instead of
/// hitting the real Dropbox API on every test run.
abstract class ProjectFileStore {
  Future<void> writeJson(String path, Map<String, dynamic> json);

  /// Returns null if nothing exists at [path] yet.
  Future<Map<String, dynamic>?> readJson(String path);

  Future<void> writeBytes(String path, Uint8List bytes);

  Future<Uint8List?> readBytes(String path);

  /// Names of immediate file entries directly under [folderPath] (not
  /// recursive) — used to list e.g. a project's `reports/` folder.
  Future<List<String>> listFileNames(String folderPath);

  Future<void> createFolder(String path);

  /// Shares [path] (must already exist) with [withEmail], read-only.
  /// Returns the shared_folder_id.
  Future<String> shareFolder(String path, {required String withEmail});
}

/// Real implementation, backed by [DropboxService] — every path is an
/// absolute Dropbox path such as `/工地A/reports/2026-07-14.json`.
class DropboxProjectFileStore implements ProjectFileStore {
  DropboxProjectFileStore({DropboxService? service})
    : _service = service ?? DropboxService.instance;

  final DropboxService _service;

  @override
  Future<void> writeJson(String path, Map<String, dynamic> json) =>
      _service.uploadJson(json, path);

  @override
  Future<Map<String, dynamic>?> readJson(String path) async {
    try {
      return await _service.downloadJson(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      _service.uploadBytes(bytes, path);

  @override
  Future<Uint8List?> readBytes(String path) async {
    try {
      return await _service.downloadFile(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> listFileNames(String folderPath) async {
    final entries = await _service.listFolder(folderPath);
    return entries
        .where((e) => e['.tag'] == 'file')
        .map((e) => e['name'] as String)
        .toList();
  }

  @override
  Future<void> createFolder(String path) => _service.createFolder(path);

  @override
  Future<String> shareFolder(String path, {required String withEmail}) async {
    final sharedFolderId = await _service.shareFolder(path);
    await _service.addFolderMember(sharedFolderId, withEmail);
    return sharedFolderId;
  }
}

/// In-memory fake for unit tests — no network, deterministic, and fast.
class InMemoryProjectFileStore implements ProjectFileStore {
  final Map<String, Map<String, dynamic>> _jsonFiles = {};
  final Map<String, Uint8List> _binaryFiles = {};
  final Set<String> _folders = {};
  final Map<String, String> sharedWith = {};

  @override
  Future<void> writeJson(String path, Map<String, dynamic> json) async {
    // Round-trip through jsonEncode/decode so tests see exactly what a real
    // Dropbox round-trip would produce (e.g. DateTime becomes a String).
    _jsonFiles[path] = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> readJson(String path) async =>
      _jsonFiles[path];

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _binaryFiles[path] = bytes;
  }

  @override
  Future<Uint8List?> readBytes(String path) async => _binaryFiles[path];

  @override
  Future<List<String>> listFileNames(String folderPath) async {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    final names = <String>{};
    for (final path in [..._jsonFiles.keys, ..._binaryFiles.keys]) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      if (rest.contains('/')) continue; // not an immediate child
      names.add(rest);
    }
    return names.toList();
  }

  @override
  Future<void> createFolder(String path) async {
    _folders.add(path);
  }

  @override
  Future<String> shareFolder(String path, {required String withEmail}) async {
    sharedWith[path] = withEmail;
    return 'fake_shared_folder:$path';
  }
}
