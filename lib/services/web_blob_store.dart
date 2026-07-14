import 'dart:typed_data';

import 'package:universal_io/io.dart' as io;

/// On native platforms, photos/signatures/PDFs are written to real files and
/// referenced by their path everywhere in the DB and UI. Web has no
/// filesystem, so this stands in: bytes are kept in memory keyed by a
/// synthetic "webblob://..." string, which is stored in exactly the same
/// database columns/fields that would otherwise hold a real file path.
///
/// This is process-memory only — it does not survive a page reload. That's
/// an accepted limitation for the web preview build; the Android app keeps
/// using real files via path_provider as before.
class WebBlobStore {
  WebBlobStore._();
  static final Map<String, Uint8List> _blobs = {};
  static int _counter = 0;

  static const _prefix = 'webblob://';

  static bool isBlobKey(String key) => key.startsWith(_prefix);

  static String put(Uint8List bytes, {required String suggestedName}) {
    final key = '$_prefix${_counter++}_$suggestedName';
    _blobs[key] = bytes;
    return key;
  }

  static Uint8List? get(String key) => _blobs[key];

  /// Reads bytes from either a real file path (native platforms) or a
  /// synthetic webblob:// key (web), so PDF-embedding code doesn't need to
  /// branch on platform itself.
  static Uint8List readBytes(String path) {
    if (isBlobKey(path)) {
      final bytes = _blobs[path];
      if (bytes == null) {
        throw StateError('No in-memory blob found for $path');
      }
      return bytes;
    }
    return io.File(path).readAsBytesSync();
  }
}
