import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/data/pet_photo_codec.dart';

/// What the person did in the pet photo sheet.
sealed class PetPhotoChoice {
  const PetPhotoChoice();
}

/// A compressed square JPEG, ready to save.
class PetPhotoPicked extends PetPhotoChoice {
  const PetPhotoPicked(this.bytes, this.source);
  final Uint8List bytes;

  /// `camera` or `library`.
  final String source;
}

class PetPhotoRemoved extends PetPhotoChoice {
  const PetPhotoRemoved();
}

/// Camera / library / remove sheet. Returns null when dismissed, cancelled
/// or the photo could not be read (the person is told why).
Future<PetPhotoChoice?> showPetPhotoSheet(
  BuildContext context, {
  required bool hasPhoto,
  String? petId,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final action = await showModalBottomSheet<String>(
    context: context,
    sheetAnimationStyle: AppMotion.sheet(context),
    constraints: AdaptiveLayout.sheetConstraints,
    backgroundColor: scheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pet photo', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'People use this to know which pet they are looking at.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop('camera'),
                child: const Text('Take a photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop('library'),
                child: const Text('Choose from photos'),
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => Navigator.of(sheetContext).pop('remove'),
                  child: const Text('Remove photo'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return null;
  if (action == 'remove') return const PetPhotoRemoved();
  return _pick(context, action, petId);
}

Future<PetPhotoChoice?> _pick(
  BuildContext context,
  String source,
  String? petId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void tell(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));
  try {
    // The picker already shrinks and re-encodes (HEIC → JPEG) natively, so
    // the Dart resize below works on a small file.
    final file = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) {
      AppLog.event('pet.photo_cancelled', {'source': source});
      return null;
    }
    final raw = await file.readAsBytes();
    // Off the UI thread; null for corrupt / unreadable / oversized images.
    final jpeg = await PetPhotoCodec.compress(raw);
    if (jpeg == null) {
      AppLog.event('pet.photo_failed', {
        'source': source,
        'kind': 'decode',
        'bytes': raw.length,
      });
      tell("That photo couldn't be used. Try another one.");
      return null;
    }
    AppLog.event('pet.photo_set', {
      'source': source,
      'bytes': jpeg.length,
      'petId': ?petId,
    });
    return PetPhotoPicked(jpeg, source);
  } on PlatformException catch (error, stack) {
    // image_picker reports a refused permission as `camera_access_denied` /
    // `photo_access_denied`; anything else is a picker/device problem.
    final denied = error.code.contains('access_denied');
    AppLog.error('pet.photo_failed', error, stack, {
      'source': source,
      'kind': denied ? 'permission' : 'picker',
      'code': error.code,
    });
    tell(switch ((denied, source)) {
      (true, 'camera') =>
        'Camera access is off. Turn it on in Settings, or choose from photos.',
      (true, _) =>
        'Photo access is off. Turn it on in Settings, or take a photo.',
      (false, 'camera') =>
        'Could not open the camera. Try choosing from photos.',
      _ => 'Could not open your photos. Try taking a photo.',
    });
    return null;
  } catch (error, stack) {
    AppLog.error('pet.photo_failed', error, stack, {
      'source': source,
      'kind': 'read',
    });
    tell("That photo couldn't be used. Try another one.");
    return null;
  }
}
