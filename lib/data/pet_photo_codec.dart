import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Turns a picked photo into a small square JPEG: center-cropped, at most
/// 512×512, EXIF (location, camera, orientation) stripped, ~75 quality and
/// stepped down until it fits [targetBytes]. Pure Dart (no native plugin),
/// run in a background isolate so a big photo never janks the UI.
abstract final class PetPhotoCodec {
  static const side = 512;

  /// Typical result is 30–70 KB; one download per phone per photo change.
  static const targetBytes = 80 * 1024;

  /// Server hard limit; nothing larger is ever kept or sent.
  static const maxBytes = 400 * 1024;
  static const _qualities = [75, 62, 50, 40];

  /// Fallback sides when even quality 40 at 512 px is over [targetBytes]
  /// (very noisy images); still shown sharp at avatar sizes.
  static const _fallbackSides = [384, 256];

  /// Null when the bytes are not an image this app can read (corrupt file,
  /// HEIC the picker didn’t convert, out of memory on a huge image).
  static Future<Uint8List?> compress(Uint8List source) =>
      Isolate.run(() => compressSync(source));

  @visibleForTesting
  static Uint8List? compressSync(Uint8List source) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(source);
    } on Object {
      // Truncated/corrupt data can throw inside a decoder instead of
      // returning null; both read as "can’t use this photo".
      return null;
    }
    if (decoded == null || decoded.width < 1 || decoded.height < 1) {
      return null;
    }
    // Apply the camera’s rotation to the pixels before EXIF is dropped.
    final upright = img.bakeOrientation(decoded);
    final shortSide = min(upright.width, upright.height);
    Uint8List? best;
    for (final target in [side, ..._fallbackSides]) {
      // Never upscale a small photo: it only adds bytes.
      final square = img.copyResizeCropSquare(
        upright,
        size: min(target, shortSide),
        interpolation: img.Interpolation.average,
      )..exif = img.ExifData(); // strip location and camera metadata
      for (final quality in _qualities) {
        final out = img.encodeJpg(square, quality: quality);
        if (best == null || out.length < best.length) best = out;
        if (out.length <= targetBytes) return out;
      }
    }
    // Over the soft target but under the server limit is still usable.
    return best != null && best.length <= maxBytes ? best : null;
  }
}
