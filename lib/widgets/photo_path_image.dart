import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';

import '../services/web_blob_store.dart';

/// Displays a photo/signature referenced by the app's stored "path" string,
/// whether that's a real file path (native platforms) or a synthetic
/// webblob:// key (web preview build — see WebBlobStore).
class PhotoPathImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  const PhotoPathImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (WebBlobStore.isBlobKey(path)) {
      final bytes = WebBlobStore.get(path);
      if (bytes == null) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      return Image.memory(bytes, fit: fit, width: width, height: height);
    }
    return Image.file(File(path), fit: fit, width: width, height: height);
  }
}
