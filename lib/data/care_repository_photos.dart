part of 'care_repository.dart';

/// Pet photos: saved on the phone first, uploaded straight to the bucket when
/// connected, downloaded once per key for photos other members set.
///
/// Cost: one upload (3 small calls) per photo change, one ~60 KB download per
/// new key per phone. Nothing is re-fetched while a pet's key is unchanged.
extension CarePetPhotos on CareRepository {
  /// Saves an already-compressed photo (see `PetPhotoCodec`) as this pet's
  /// photo. Works offline; the upload follows when connected.
  Future<bool> setPetPhoto(String petId, Uint8List jpeg) async {
    lastError = null;
    final pet = tryPetById(petId);
    final store = _photos;
    if (pet == null) {
      lastError = 'This pet is no longer in your household.';
      AppLog.event('pet.photo_rejected', {'petId': petId, 'reason': 'missing_pet'});
      return false;
    }
    if (store == null) {
      lastError = "Photos aren't available on this device.";
      AppLog.event('pet.photo_rejected', {'petId': petId, 'reason': 'no_store'});
      return false;
    }
    if (jpeg.isEmpty || jpeg.length > PetPhotoCodec.maxBytes) {
      lastError = 'That photo is too large. Try another one.';
      AppLog.event('pet.photo_rejected', {
        'petId': petId,
        'reason': 'size',
        'bytes': jpeg.length,
      });
      return false;
    }
    try {
      await store.writeOwn(petId, jpeg);
    } on Object catch (error, stack) {
      lastError = "Couldn't save the photo. Try again.";
      AppLog.error('pet.photo_save_failed', error, stack, {'petId': petId});
      _notify();
      return false;
    }
    final current = tryPetById(petId) ?? pet;
    _replacePet(
      current.withPhoto(
        // Unique per change, so an image cached for the old file never shows.
        photoVersion: now.microsecondsSinceEpoch,
        photoSync: PhotoSync.upload,
      ),
    );
    AppLog.event('pet.photo_saved_local', {
      'petId': petId,
      'bytes': jpeg.length,
      'offline': !isConnected,
    });
    _changed();
    if (isConnected) {
      AppLog.unawaitedLogged(syncPetPhotos(), 'pet.photo_upload_failed');
    }
    return true;
  }

  /// Removes the pet's photo here, and from the household when connected
  /// (queued if offline).
  Future<bool> removePetPhoto(String petId) async {
    lastError = null;
    final pet = tryPetById(petId);
    if (pet == null) {
      AppLog.event('pet.photo_rejected', {'petId': petId, 'reason': 'missing_pet'});
      return false;
    }
    try {
      await _photos?.deleteOwn(petId);
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_delete_failed', error, stack, {'petId': petId});
    }
    // Only a photo the household already has needs a server call.
    final needsServer = pet.photoKey != null;
    _replacePet(
      pet.withPhoto(
        photoVersion: 0,
        photoSync: needsServer ? PhotoSync.remove : PhotoSync.none,
        photoPath: null,
      ),
    );
    AppLog.event('pet.photo_removed', {
      'petId': petId,
      'offline': !isConnected,
    });
    _changed();
    if (isConnected && needsServer) {
      AppLog.unawaitedLogged(syncPetPhotos(), 'pet.photo_upload_failed');
    }
    return true;
  }

  /// Sends pending photo uploads/removals. One run at a time; safe to call
  /// from sync, connect, resume or right after a change.
  Future<void> syncPetPhotos() {
    return _photoSyncRunning ??= _syncPetPhotos().whenComplete(
      () => _photoSyncRunning = null,
    );
  }

  Future<void> _syncPetPhotos() async {
    final api = _api;
    final store = _photos;
    if (api == null || store == null || !isConnected) return;
    // Loop so a change made during an upload is sent in the same run.
    for (var pass = 0; pass < 3; pass++) {
      final pending = [
        for (final pet in _pets)
          if (pet.photoSync != PhotoSync.none) pet,
      ];
      if (pending.isEmpty) return;
      for (final pet in pending) {
        final keepGoing = pet.photoSync == PhotoSync.upload
            ? await _uploadPhoto(api, store, pet)
            : await _removePhotoRemote(api, pet);
        if (!keepGoing) return;
      }
    }
  }

  /// False when the rest of the queue should wait (offline, signed out).
  Future<bool> _uploadPhoto(
    HouseholdApi api,
    PetPhotoStore store,
    Pet pet,
  ) async {
    final version = pet.photoVersion;
    final Uint8List? bytes;
    try {
      bytes = await store.readOwn(pet.id);
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_read_failed', error, stack, {'petId': pet.id});
      return true;
    }
    if (bytes == null) {
      // File gone (storage cleared): nothing to send.
      _replacePet(pet.withPhoto(photoVersion: 0, photoSync: PhotoSync.none));
      AppLog.event('pet.photo_upload_failed', {
        'petId': pet.id,
        'kind': 'missing_file',
      });
      _changed();
      return true;
    }
    AppLog.event('pet.photo_upload_started', {
      'petId': pet.id,
      'bytes': bytes.length,
    });
    var step = 'start';
    try {
      final ticket = await api.startPetPhotoUpload(pet.id, bytes.length);
      step = 'put';
      await _photoTransfer.put(ticket.url, ticket.headers, bytes);
      step = 'attach';
      final attached = await api.attachPetPhoto(pet.id, ticket.photoKey);
      final current = tryPetById(pet.id);
      if (current == null) return true;
      // A newer photo picked meanwhile stays pending (latest wins).
      final superseded =
          current.photoVersion != version ||
          current.photoSync != PhotoSync.upload;
      _replacePet(
        current.withPhoto(
          photoKey: attached.photoKey,
          photoUrl: attached.photoUrl,
          photoSync: superseded ? current.photoSync : PhotoSync.none,
        ),
      );
      AppLog.event('pet.photo_upload_completed', {
        'petId': pet.id,
        'bytes': bytes.length,
      });
      _changed();
      return true;
    } on HouseholdException catch (error) {
      AppLog.event('pet.photo_upload_failed', {
        'petId': pet.id,
        'kind': error.kind.name,
        'step': step,
        if (error.status != null) 'status': error.status,
      });
      switch (error.kind) {
        case HouseholdErrorKind.unauthorized:
          await _dropSession('photo_unauthorized', error);
          return false;
        case HouseholdErrorKind.offline:
          return false;
        case HouseholdErrorKind.notFound:
          // Pet removed on the server: stop retrying, keep the local photo.
          _replacePet(pet.withPhoto(photoSync: PhotoSync.none));
          _changed();
          return true;
        case HouseholdErrorKind.invalid when step == 'start':
          // Refused size: retrying would fail the same way.
          _replacePet(pet.withPhoto(photoSync: PhotoSync.none));
          _changed();
          return true;
        default:
          // "Didn't finish uploading" / server hiccup: retried next sync.
          return true;
      }
    } on PhotoTransferException catch (error) {
      AppLog.event('pet.photo_upload_failed', {
        'petId': pet.id,
        'kind': error.kind,
        'step': step,
        if (error.status != null) 'status': error.status,
      });
      return error.kind != 'offline';
    }
  }

  Future<bool> _removePhotoRemote(HouseholdApi api, Pet pet) async {
    try {
      await api.removePetPhoto(pet.id);
    } on HouseholdException catch (error) {
      AppLog.event('pet.photo_remove_failed', {
        'petId': pet.id,
        'kind': error.kind.name,
      });
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('photo_unauthorized', error);
        return false;
      }
      if (error.kind == HouseholdErrorKind.offline) return false;
      if (error.kind != HouseholdErrorKind.notFound) return true;
    }
    final current = tryPetById(pet.id);
    if (current != null && current.photoSync == PhotoSync.remove) {
      _replacePet(
        current.withPhoto(
          photoKey: null,
          photoUrl: null,
          photoSync: PhotoSync.none,
        ),
      );
      _changed();
    }
    AppLog.event('pet.photo_remove_synced', {'petId': pet.id});
    return true;
  }

  /// Downloads photos other members set (once per key) and deletes files no
  /// pet uses any more. Never refetches a key already on disk.
  Future<void> refreshPhotoCache() async {
    final store = _photos;
    if (store == null) return;
    try {
      await store.init();
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_store_failed', error, stack);
      return;
    }
    var changed = false;
    for (final pet in List.of(_pets)) {
      final key = pet.photoKey;
      if (key == null ||
          pet.photoVersion != 0 ||
          pet.photoSync != PhotoSync.none) {
        continue;
      }
      if (store.isCached(key)) {
        if (_photoCacheHitLogged.add(key)) {
          AppLog.event('pet.photo_cache_hit', {'petId': pet.id});
        }
        continue;
      }
      final url = pet.photoUrl;
      if (url == null) continue;
      try {
        final bytes = await _photoTransfer.get(url);
        await store.writeCache(key, bytes);
        _photoCacheHitLogged.add(key);
        changed = true;
        AppLog.event('pet.photo_downloaded', {
          'petId': pet.id,
          'bytes': bytes.length,
        });
      } on PhotoTransferException catch (error) {
        AppLog.event('pet.photo_download_failed', {
          'petId': pet.id,
          'kind': error.kind,
          if (error.status != null) 'status': error.status,
        });
        if (error.kind == 'offline') break;
      } on Object catch (error, stack) {
        AppLog.error('pet.photo_download_failed', error, stack, {
          'petId': pet.id,
        });
      }
    }
    try {
      final removed = await store.prune(
        keepPetIds: {
          for (final pet in _pets)
            if (pet.photoVersion != 0) pet.id,
        },
        keepKeys: {
          for (final pet in _pets) ?pet.photoKey,
        },
      );
      if (removed > 0) {
        AppLog.event('pet.photo_cache_pruned', {'files': removed});
      }
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_prune_failed', error, stack);
    }
    if (changed && _resolvePhotoPaths()) _notify();
  }

  void _replacePet(Pet pet) {
    final index = _pets.indexWhere((item) => item.id == pet.id);
    if (index < 0) return;
    _pets[index] = pet;
    _resolvePhotoPaths();
  }

  /// Fills each pet's [Pet.photoPath] from what is on disk. No file IO:
  /// own photos are tracked by version, the cache by an in-memory listing.
  /// Returns true when any path changed.
  bool _resolvePhotoPaths() {
    final store = _photos;
    if (store == null || !store.isReady) return false;
    var changed = false;
    for (var i = 0; i < _pets.length; i++) {
      final pet = _pets[i];
      final key = pet.photoKey;
      final path = switch (pet) {
        Pet(photoSync: PhotoSync.remove) => null,
        Pet(photoVersion: != 0) => store.ownPath(pet.id),
        _ when key != null && store.isCached(key) => store.cachePath(key),
        _ => null,
      };
      if (path != pet.photoPath) {
        _pets[i] = pet.withPhoto(photoPath: path);
        changed = true;
      }
    }
    return changed;
  }

  /// Server pets carry no local photo state; keep this phone's pending work
  /// and drop its own file when someone else set a newer photo.
  List<Pet> _mergePhotoState(List<Pet> incoming) {
    final local = {for (final pet in _pets) pet.id: pet};
    final stale = <String>[];
    final merged = [
      for (final server in incoming)
        () {
          final mine = local[server.id];
          if (mine == null) return server;
          return switch (mine.photoSync) {
            PhotoSync.upload => server.withPhoto(
              photoVersion: mine.photoVersion,
              photoSync: PhotoSync.upload,
            ),
            PhotoSync.remove => server.withPhoto(
              photoVersion: 0,
              photoSync: PhotoSync.remove,
            ),
            PhotoSync.none when mine.photoVersion != 0 =>
              server.photoKey == mine.photoKey
                  ? server.withPhoto(photoVersion: mine.photoVersion)
                  : () {
                      stale.add(server.id);
                      return server;
                    }(),
            PhotoSync.none => server,
          };
        }(),
    ];
    final store = _photos;
    if (store != null) {
      for (final id in stale) {
        AppLog.unawaitedLogged(store.deleteOwn(id), 'pet.photo_delete_failed');
      }
    }
    return merged;
  }

  /// The household is gone but the pets stay: keep each visible photo as
  /// this phone's own, pending upload should the person share again.
  Future<void> _keepPhotosAfterHouseholdGone() async {
    final store = _photos;
    for (var i = 0; i < _pets.length; i++) {
      final pet = _pets[i];
      var version = pet.photoVersion;
      final key = pet.photoKey;
      if (store != null &&
          version == 0 &&
          key != null &&
          pet.photoSync == PhotoSync.none) {
        try {
          if (await store.adoptCached(key, pet.id)) {
            version = now.microsecondsSinceEpoch;
          }
        } on Object catch (error, stack) {
          AppLog.error('pet.photo_adopt_failed', error, stack, {
            'petId': pet.id,
          });
        }
      }
      _pets[i] = pet.withPhoto(
        photoKey: null,
        photoUrl: null,
        photoVersion: version,
        photoSync: version == 0 ? PhotoSync.none : PhotoSync.upload,
      );
    }
    _resolvePhotoPaths();
  }

  Future<void> _clearPhotos() async {
    _photoCacheHitLogged.clear();
    try {
      await _photos?.clearAll();
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_clear_failed', error, stack);
    }
  }
}
