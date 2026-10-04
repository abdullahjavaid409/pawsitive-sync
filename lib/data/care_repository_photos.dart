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
      AppLog.event('pet.photo_rejected', {
        'petId': petId,
        'reason': 'missing_pet',
      });
      return false;
    }
    if (store == null) {
      lastError = "Photos aren't available on this device.";
      AppLog.event('pet.photo_rejected', {
        'petId': petId,
        'reason': 'no_store',
      });
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
    } on FileSystemException catch (error, stack) {
      // Usually a full disk (ENOSPC). Nothing changed, the old photo stays.
      lastError = "Couldn't save the photo. Your phone may be out of space.";
      AppLog.error('pet.photo_save_failed', error, stack, {
        'petId': petId,
        'kind': 'disk',
        'code': error.osError?.errorCode ?? 0,
      });
      _notify();
      return false;
    } on Object catch (error, stack) {
      lastError = "Couldn't save the photo. Try again.";
      AppLog.error('pet.photo_save_failed', error, stack, {
        'petId': petId,
        'kind': 'unknown',
      });
      _notify();
      return false;
    }
    final current = tryPetById(petId) ?? pet;
    _replacePet(
      current.withPhoto(
        // Unique per change, so an image cached for the old file never shows.
        photoVersion: _nextPhotoVersion(current),
        photoSync: PhotoSync.upload,
      ),
    );
    AppLog.event('pet.photo_saved_local', {
      'petId': petId,
      'bytes': jpeg.length,
      'offline': !isConnected,
    });
    _changed();
    // The pending flag must be on disk before the upload starts, so an app
    // killed mid-upload retries on the next launch instead of forgetting.
    await flushPersist();
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
      AppLog.event('pet.photo_rejected', {
        'petId': petId,
        'reason': 'missing_pet',
      });
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
    await flushPersist(); // same kill-safety as [setPetPhoto]
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

  /// 0..1 while this pet's photo is uploading, else null.
  double? photoUploadProgress(String petId) => _photoProgress[petId];

  Future<void> _syncPetPhotos() async {
    final api = _api;
    final store = _photos;
    if (api == null || store == null || !isConnected) return;
    _photoRetryTimer?.cancel();
    // Loop so a change made during an upload is sent in the same run.
    for (var pass = 0; pass < 3; pass++) {
      final pending = [
        for (final pet in _pets)
          if (pet.photoSync != PhotoSync.none) pet,
      ];
      if (pending.isEmpty) {
        _photoRetryAttempt = 0;
        return;
      }
      for (final pet in pending) {
        final keepGoing = pet.photoSync == PhotoSync.upload
            ? await _uploadPhoto(api, store, pet)
            : await _removePhotoRemote(api, pet);
        if (!keepGoing) {
          // Network trouble: the rest would fail too. Back off and retry.
          _schedulePhotoRetry();
          return;
        }
      }
    }
  }

  void _schedulePhotoRetry() {
    if (!isConnected) return; // signed out: nothing to retry
    final delays = CareRepository.photoRetryDelays;
    if (_photoRetryAttempt >= delays.length) {
      AppLog.event('pet.photo_retry_deferred', {'until': 'next_sync'});
      return;
    }
    final delay = delays[_photoRetryAttempt++];
    AppLog.event('pet.photo_retry_scheduled', {
      'attempt': _photoRetryAttempt,
      'seconds': delay.inSeconds,
    });
    _photoRetryTimer?.cancel();
    _photoRetryTimer = Timer(delay, () {
      AppLog.unawaitedLogged(syncPetPhotos(), 'pet.photo_upload_failed');
    });
  }

  void _setProgress(String petId, double? value) {
    final before = _photoProgress[petId];
    if (value == null) {
      if (_photoProgress.remove(petId) != null) _notify();
      return;
    }
    // Repaint at most every 10% (and at the ends), not per network chunk.
    if (before == null || value >= 1 || (value - before).abs() >= 0.1) {
      _photoProgress[petId] = value;
      _notify();
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
      'attempt': _photoRetryAttempt + 1,
    });
    final watch = Stopwatch()..start();
    _setProgress(pet.id, 0);
    var step = 'start';
    try {
      // Two attempts: a presigned PUT URL lives 5 minutes, so a rejected PUT
      // (expired / clock skew) gets one fresh ticket right away.
      ({String photoKey, String? photoUrl})? attached;
      for (var attempt = 1; attached == null; attempt++) {
        step = 'start';
        final ticket = await api.startPetPhotoUpload(pet.id, bytes.length);
        step = 'put';
        try {
          await _photoTransfer.put(
            ticket.url,
            ticket.headers,
            bytes,
            onProgress: (sent) => _setProgress(pet.id, sent),
          );
        } on PhotoTransferException catch (error) {
          if (error.kind != 'rejected' || attempt >= 2) rethrow;
          AppLog.event('pet.photo_upload_retry', {
            'petId': pet.id,
            'step': step,
            if (error.status != null) 'status': error.status,
          });
          continue;
        }
        step = 'attach';
        attached = await _attachWithRetry(api, pet.id, ticket.photoKey);
      }
      final current = tryPetById(pet.id);
      if (current == null) return true; // pet removed locally meanwhile
      // A newer photo (or a removal) picked during the upload stays pending
      // and is sent next: latest change wins.
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
        'ms': watch.elapsedMilliseconds,
      });
      _photoRetryAttempt = 0;
      _setProgress(pet.id, null);
      _changed();
      return true;
    } on HouseholdException catch (error) {
      _setProgress(pet.id, null);
      AppLog.event('pet.photo_upload_failed', {
        'petId': pet.id,
        'kind': error.timedOut ? 'timeout' : error.kind.name,
        'step': step,
        'attempt': _photoRetryAttempt + 1,
        'ms': watch.elapsedMilliseconds,
        if (error.status != null) 'status': error.status,
      });
      switch (error.kind) {
        case HouseholdErrorKind.unauthorized:
          await _dropSession('photo_unauthorized', error);
          return false;
        case HouseholdErrorKind.offline:
          return false; // offline or timed out: keep pending, back off
        case HouseholdErrorKind.notFound:
          // Pet deleted on the server mid-upload: drop the pending upload
          // (retrying can never succeed); the local photo stays.
          _dropPendingUpload(pet.id, version);
          return true;
        case HouseholdErrorKind.invalid when step == 'start':
          // Size refused: retrying would fail the same way.
          _dropPendingUpload(pet.id, version);
          return true;
        default:
          // Attach still failing / server hiccup: stays pending and the next
          // sync restarts from a fresh ticket (the orphan object costs KB).
          return true;
      }
    } on PhotoTransferException catch (error) {
      _setProgress(pet.id, null);
      AppLog.event('pet.photo_upload_failed', {
        'petId': pet.id,
        'kind': error.kind,
        'step': step,
        'attempt': _photoRetryAttempt + 1,
        'ms': watch.elapsedMilliseconds,
        if (error.status != null) 'status': error.status,
      });
      // Pending stays set either way; network failures also back off.
      return !error.isNetwork;
    }
  }

  /// The bytes are in the bucket; a dropped attach is retried once before
  /// giving up (the server HEADs the object, so a retry is always safe).
  Future<({String photoKey, String? photoUrl})> _attachWithRetry(
    HouseholdApi api,
    String petId,
    String photoKey,
  ) async {
    try {
      return await api.attachPetPhoto(petId, photoKey);
    } on HouseholdException catch (error) {
      // Not on offline/timeout: hammering a bad link helps no one; the
      // backoff restarts the whole upload later.
      final retryable =
          error.kind == HouseholdErrorKind.server ||
          error.kind == HouseholdErrorKind.invalid;
      if (!retryable) rethrow;
      AppLog.event('pet.photo_upload_retry', {
        'petId': petId,
        'step': 'attach',
        'kind': error.kind.name,
      });
      return api.attachPetPhoto(petId, photoKey);
    }
  }

  void _dropPendingUpload(String petId, int version) {
    final current = tryPetById(petId);
    if (current == null ||
        current.photoVersion != version ||
        current.photoSync != PhotoSync.upload) {
      return; // a newer change replaced this one; leave it pending
    }
    _replacePet(current.withPhoto(photoSync: PhotoSync.none));
    _changed();
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
  Future<void> refreshPhotoCache() {
    // A second caller (sync + connect overlapping) joins the running pass.
    return _photoCacheRunning ??= _refreshPhotoCache().whenComplete(
      () => _photoCacheRunning = null,
    );
  }

  Future<void> _refreshPhotoCache() async {
    final store = _photos;
    if (store == null) return;
    try {
      await store.init();
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_store_failed', error, stack);
      return;
    }
    var changed = false;
    // Pets whose presigned URL the bucket refused (expired after 24h when
    // the app stayed open); retried once with fresh URLs from the server.
    final expired = <String>{};
    Future<void> download(Pet pet, String key, String url) async {
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
        if (error.kind == 'rejected') expired.add(pet.id);
        // Offline: the cached/own photo or the species mark keeps showing.
        if (error.isNetwork || error.kind == 'cancelled') throw error;
      } on Object catch (error, stack) {
        AppLog.error('pet.photo_download_failed', error, stack, {
          'petId': pet.id,
        });
      }
    }

    List<Pet> needed() => [
      for (final pet in _pets)
        // Only photos set elsewhere; own photos are already on disk.
        if (pet.photoKey != null &&
            pet.photoVersion == 0 &&
            pet.photoSync == PhotoSync.none)
          pet,
    ];

    try {
      for (final pet in needed()) {
        final key = pet.photoKey!;
        if (await store.verifyCached(key)) {
          // Same key as last time: never refetch (URLs expire, keys don't).
          if (_photoCacheHitLogged.add(key)) {
            AppLog.event('pet.photo_cache_hit', {'petId': pet.id});
          }
          continue;
        }
        final url = pet.photoUrl;
        if (url != null) await download(pet, key, url);
      }
      if (expired.isNotEmpty) await _retryExpiredDownloads(expired, download);
    } on PhotoTransferException {
      // Offline: stop; the next sync tries again.
    }
    try {
      final removed = await store.prune(
        keepPetIds: {
          for (final pet in _pets)
            if (pet.photoVersion != 0) pet.id,
        },
        keepKeys: {for (final pet in _pets) ?pet.photoKey},
      );
      if (removed > 0) {
        AppLog.event('pet.photo_cache_pruned', {'files': removed});
      }
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_prune_failed', error, stack);
    }
    if (changed && _resolvePhotoPaths()) _notify();
  }

  /// One extra GET /v1/household for fresh 24h URLs, only when a download
  /// was refused — never on a normal sync.
  Future<void> _retryExpiredDownloads(
    Set<String> petIds,
    Future<void> Function(Pet pet, String key, String url) download,
  ) async {
    final api = _api;
    if (api == null || !isConnected) return;
    final HouseholdSnapshot fresh;
    try {
      fresh = await api.fetchHousehold();
    } on HouseholdException catch (error) {
      AppLog.event('pet.photo_url_refresh_failed', {'kind': error.kind.name});
      return;
    }
    AppLog.event('pet.photo_url_refreshed', {'pets': petIds.length});
    for (final server in fresh.pets) {
      final pet = tryPetById(server.id);
      final key = server.photoKey;
      final url = server.photoUrl;
      // Only if the key is still the one we wanted; a new key is picked up
      // by the next full sync.
      if (pet == null ||
          !petIds.contains(pet.id) ||
          key == null ||
          url == null ||
          key != pet.photoKey) {
        continue;
      }
      _replacePet(pet.withPhoto(photoUrl: url));
      await download(pet, key, url);
    }
  }

  static int _maxInt(int a, int b) => a > b ? a : b;

  /// Strictly increasing per pet even with a frozen clock (tests) or a clock
  /// moved backwards, so the image cache can never show an older photo.
  int _nextPhotoVersion(Pet pet) =>
      _maxInt(now.microsecondsSinceEpoch, pet.photoVersion + 1);

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
    _stopPhotoWork();
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
            version = _nextPhotoVersion(pet);
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

  /// Stops photo network work (timers, downloads) when the household goes.
  void _stopPhotoWork() {
    _photoRetryTimer?.cancel();
    _photoRetryTimer = null;
    _photoRetryAttempt = 0;
    _photoProgress.clear();
    _photoTransfer.cancelDownloads();
  }

  Future<void> _clearPhotos() async {
    _stopPhotoWork();
    _photoCacheHitLogged.clear();
    try {
      await _photos?.clearAll();
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_clear_failed', error, stack);
    }
  }
}
