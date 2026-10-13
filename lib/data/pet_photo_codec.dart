import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Turns a picked photo into a small square JPEG: center-cropped, at most
/// 320×320 (the largest portrait is 80pt = 240px at 3x), EXIF (location,
/// camera, orientation) stripped, ~72 quality and stepped down until it
/// fits [targetBytes]. Small files keep storage and egress near free. Pure Dart (no native plugin),
/// run in a background isolate so a big photo never janks the UI.
abstract final class PetPhotoCodec {
  static const side = 320;

  /// Typical result is 12–25 KB; one download per phone per photo change.
  static const targetBytes = 32 * 1024;

  /// Server hard limit; nothing larger is ever kept or sent. Unchanged so
  /// photos from older app versions still upload.
  static const maxBytes = 400 * 1024;
  static const _qualities = [72, 60, 50, 40];

  /// Largest picked file we will read at all. The picker already shrinks
  /// photos to 1024px, so anything this big is a format it couldn't shrink.
  static const maxSourceBytes = 25 * 1024 * 1024;

  /// Largest image we will decode (width × height). A 48MP phone photo is
  /// under this; a decompression bomb or panorama is not.
  static const maxSourcePixels = 60 * 1000 * 1000;

  /// Fallback sides when even quality 40 at [side] is over [targetBytes]
  /// (very noisy images); still sharp at avatar sizes.
  static const _fallbackSides = [256, 192];

  /// Null when the bytes are not an image this app can read (corrupt file,
  /// HEIC the picker didn’t convert, out of memory on a huge image).
  static Future<Uint8List?> compress(Uint8List source) async {
    if (source.length > maxSourceBytes) return null;
    try {
      return await Isolate.run(() => compressSync(source));
    } on Object {
      // The worker died (e.g. out of memory on a huge image): same as an
      // unreadable photo, never a crash.
      return null;
    }
  }

  @visibleForTesting
  static Uint8List? compressSync(Uint8List source) {
    if (source.isEmpty || source.length > maxSourceBytes) return null;
    final img.Image? decoded;
    try {
      // Read the header first so a huge image is refused before decoding.
      final info = img.findDecoderForData(source)?.startDecode(source);
      if (info != null && info.width * info.height > maxSourcePixels) {
        return null;
      }
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
