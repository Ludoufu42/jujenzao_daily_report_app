import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

import 'web_blob_store.dart';

const _heicExtensions = {'.heic', '.heif'};

class PhotoImportException implements Exception {
  final String message;
  const PhotoImportException(this.message);

  @override
  String toString() => message;
}

/// Copies picked photos into the app's own persistent storage (rather than
/// trusting image_picker's temp/cache path to still exist weeks later when
/// the PDF gets regenerated), converting HEIC/HEIF — which neither Flutter's
/// Image widget nor the `pdf` package can decode — to JPEG along the way.
class PhotoImportService {
  PhotoImportService._internal();
  static final PhotoImportService instance = PhotoImportService._internal();

  Future<Directory> _photosDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'report_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the stable, app-owned path for the imported photo. On web
  /// there's no real filesystem (and no working HEIC decoder), so the bytes
  /// go straight into the in-memory blob store under a synthetic key.
  Future<String> importPhoto(XFile file) async {
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return WebBlobStore.put(bytes, suggestedName: p.basename(file.path));
    }

    final photosDir = await _photosDir();
    final ext = p.extension(file.path).toLowerCase();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    if (_heicExtensions.contains(ext)) {
      final targetPath = p.join(photosDir.path, 'photo_$stamp.jpg');
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        format: CompressFormat.jpeg,
        quality: 90,
      );
      if (result == null) {
        throw const PhotoImportException(
          '這張照片是 HEIC 格式，轉檔失敗，請改用其他格式的照片',
        );
      }
      return result.path;
    }

    final safeExt = ext.isEmpty ? '.jpg' : ext;
    final targetPath = p.join(photosDir.path, 'photo_$stamp$safeExt');
    await File(file.path).copy(targetPath);
    return targetPath;
  }

  Future<List<String>> importPhotos(List<XFile> files) async {
    final paths = <String>[];
    for (final file in files) {
      paths.add(await importPhoto(file));
    }
    return paths;
  }
}
