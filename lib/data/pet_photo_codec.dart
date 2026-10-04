import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Turns a picked photo into a small square JPEG: center-cropped, at most
/// 512×512, EXIF (location, camera, orientation) stripped, ~75 quality and
/// stepped down until it fits [targetBytes]. Pure Dart, run off the UI thread.
abstract final class PetPhotoCodec {
  static const side = 512;
  static const targetBytes = 80 * 1024;

  /// Server hard limit; nothing larger is ever kept or sent.
  static const maxBytes = 400 * 1024;
  static const _qualities = [75, 62, 50, 40];

  /// Null when the bytes are not an image this app can read.
  static Future<Uint8List?> compress(Uint8List source) =>
      Isolate.run(() => compressSync(source));

  @visibleForTesting
  static Uint8List? compressSync(Uint8List source) {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    // Apply the camera's rotation to the pixels before EXIF is dropped.
    final upright = img.bakeOrientation(decoded);
    final size = min(side, min(upright.width, upright.height));
    final square = img.copyResizeCropSquare(
      upright,
      size: size,
      interpolation: img.Interpolation.average,
    )..exif = img.ExifData();
    Uint8List? out;
    for (final quality in _qualities) {
      out = img.encodeJpg(square, quality: quality);
      if (out.length <= targetBytes) break;
    }
    return out != null && out.length <= maxBytes ? out : null;
  }
}
