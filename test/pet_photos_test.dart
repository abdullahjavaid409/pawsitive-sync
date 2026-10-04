import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/pet_photo_codec.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_test_helpers.dart';
import 'support/sample_household.dart';

Map<String, Object?> _field(String event) =>
    AppLog.testRecords.lastWhere((r) => r.name == event).fields;

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    // No timers unless a test opts in.
    CareRepository.photoRetryDelays = const [];
    dir = await Directory.systemTemp.createTemp('pet_photos_test');
  });

  tearDown(() async {
    AppLog.disableTestCapture();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('PetPhotoCodec', () {
    test('big photo → 512 square JPEG under 80 KB with no EXIF', () {
      final out = PetPhotoCodec.compressSync(sampleJpeg(2400, 1600))!;
      expect(out.length, lessThanOrEqualTo(PetPhotoCodec.targetBytes));
      final decoded = img.decodeJpg(out)!;
      expect((decoded.width, decoded.height), (512, 512));
      expect(decoded.exif.isEmpty, isTrue);
      // No APP1/"Exif" marker anywhere in the file (location stripped).
      expect(latin1.decode(out, allowInvalid: true).contains('Exif'), isFalse);
    });

    test('noisy photo still fits the target by stepping quality/size down', () {
      final out = PetPhotoCodec.compressSync(
        sampleJpeg(1600, 1600, noisy: true),
      )!;
      expect(out.length, lessThanOrEqualTo(PetPhotoCodec.targetBytes));
    });

    test('never upscales a small photo; corrupt bytes give null', () {
      final small = img.decodeJpg(
        PetPhotoCodec.compressSync(sampleJpeg(300, 200))!,
      )!;
      expect((small.width, small.height), (200, 200));
      expect(
        PetPhotoCodec.compressSync(Uint8List.fromList([1, 2, 3, 4])),
        isNull,
      );
      // Truncated JPEG (download cut short) must not throw either.
      final cut = sampleJpeg(400, 400);
      expect(
        () => PetPhotoCodec.compressSync(
          Uint8List.sublistView(cut, 0, cut.length ~/ 3),
        ),
        returnsNormally,
      );
    });
  });

  test('old saved household without photo fields still loads', () async {
    SharedPreferences.setMockInitialValues({
      'household_v2': jsonEncode({
        'memberId': 'you',
        'members': [
          {'id': 'you', 'name': 'You', 'role': 'owner', 'isYou': true},
        ],
        'pets': [
          {'id': 'p1', 'name': 'Miso', 'species': 'cat'},
        ],
      }),
    });
    final saved = await HouseholdStore().read();
    final pet = saved!.pets.single;
    expect(pet.photoKey, isNull);
    expect(pet.photoVersion, 0);
    expect(pet.photoSync, PhotoSync.none);
  });

  test('solo phone: photo saved locally, never uploaded', () async {
    final transfer = FakeTransfer();
    final care = CareRepository(
      store: HouseholdStore(),
      photoStore: PetPhotoStore(baseDir: () async => dir),
      photoTransfer: transfer,
    );
    await care.restore();
    final petId = (await care.addPet(name: 'Miso', species: Species.cat))!;
    expect(await care.setPetPhoto(petId, sampleJpeg(64, 64)), isTrue);
    final pet = care.petById(petId);
    expect(File(pet.photoPath!).existsSync(), isTrue);
    expect(pet.photoPath, endsWith('pet_photos/$petId.jpg'));
    expect(transfer.puts, isEmpty);
    expect(_field('pet.photo_saved_local')['offline'], isTrue);
    // The picker's source rides on the one saved line (no pet.photo_set).
    expect(
      await care.setPetPhoto(petId, sampleJpeg(32, 32), source: 'camera'),
      isTrue,
    );
    expect(
      AppLog.testRecords
          .lastWhere((r) => r.name == 'pet.photo_saved_local')
          .fields['source'],
      'camera',
    );
    // Survives a restart: the store keeps version + pending flag.
    final again = CareRepository(
      store: HouseholdStore(),
      photoStore: PetPhotoStore(baseDir: () async => dir),
    );
    await again.restore();
    expect(again.petById(petId).photoPath, pet.photoPath);
    expect(again.petById(petId).photoSync, PhotoSync.upload);
  });

  test(
    'offline save keeps the photo pending, uploads on reconnect, once',
    () async {
      final routes = uploadRoutes('households/h/pets/miso/a1.jpg');
      routes['POST /v1/pets/miso/photo/upload']!.insert(0, const Offline());
      final (care, adapter, transfer) = await connectedCare(
        dir,
        routes: routes,
      );
      final jpeg = sampleJpeg(64, 64);

      expect(await care.setPetPhoto('miso', jpeg), isTrue);
      await care.syncPetPhotos();
      expect(care.petById('miso').photoSync, PhotoSync.upload);
      expect(care.petById('miso').hasPhoto, isTrue); // still shown offline
      expect(_field('pet.photo_upload_failed')['kind'], 'offline');
      // The pending flag is already on disk (app may be killed now).
      final saved = await HouseholdStore().read();
      expect(saved!.pets.single.photoSync, PhotoSync.upload);

      await care.syncPetPhotos(); // "reconnect"
      final pet = care.petById('miso');
      expect(pet.photoSync, PhotoSync.none);
      expect(pet.photoKey, 'households/h/pets/miso/a1.jpg');
      expect(transfer.puts.single.$2['content-type'], 'image/jpeg');
      expect(transfer.puts.single.$3, jpeg.length);
      expect(adapter.count('PUT /v1/pets/miso/photo'), 1);
      final done = _field('pet.photo_upload_completed');
      expect(done['bytes'], jpeg.length);
      expect(done, contains('ms'));

      // Unchanged photo: nothing re-uploaded, and our own photo is never
      // downloaded back even though the snapshot now carries its key.
      adapter.routes['GET /v1/household'] = [
        Answer(
          200,
          snapshotWithPhoto(
            photoKey: 'households/h/pets/miso/a1.jpg',
            photoUrl: 'https://b/a1',
          ),
        ),
      ];
      await care.sync(force: true);
      expect(transfer.puts, hasLength(1));
      expect(transfer.gets, isEmpty);
      expect(care.petById('miso').photoVersion, isNot(0)); // own file kept
    },
  );

  test('slow PUT times out → pending kept, retried with backoff', () async {
    CareRepository.photoRetryDelays = const [Duration(milliseconds: 20)];
    final (care, _, transfer) = await connectedCare(
      dir,
      routes: uploadRoutes('households/h/pets/miso/t1.jpg'),
    );
    transfer.putFailures.add(const PhotoTransferException('timeout'));
    await care.setPetPhoto('miso', sampleJpeg(64, 64));
    await care.syncPetPhotos();
    final failed = _field('pet.photo_upload_failed');
    expect(failed['kind'], 'timeout');
    expect(failed['attempt'], 1);
    expect(care.petById('miso').photoSync, PhotoSync.upload);
    expect(AppLog.logged('pet.photo_retry_scheduled'), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await care.syncPetPhotos();
    expect(care.petById('miso').photoSync, PhotoSync.none);
    expect(transfer.puts, hasLength(2));
    // Progress was reported and cleared when done.
    expect(transfer.progress, contains(1.0));
    expect(care.photoUploadProgress('miso'), isNull);
  });

  test('expired upload URL restarts with a fresh ticket', () async {
    final routes = uploadRoutes('households/h/pets/miso/e1.jpg');
    final (care, adapter, transfer) = await connectedCare(dir, routes: routes);
    transfer.putFailures.add(const PhotoTransferException('rejected', 403));
    await care.setPetPhoto('miso', sampleJpeg(64, 64));
    await care.syncPetPhotos();
    expect(adapter.count('POST /v1/pets/miso/photo/upload'), 2);
    expect(care.petById('miso').photoSync, PhotoSync.none);
  });

  test(
    'attach fails once → retried; pet gone (404) → pending dropped',
    () async {
      final routes = uploadRoutes('households/h/pets/miso/r1.jpg');
      routes['PUT /v1/pets/miso/photo']!.insert(
        0,
        const Answer(400, {
          'error': "The photo didn't finish uploading. Try again.",
        }),
      );
      final (care, adapter, _) = await connectedCare(dir, routes: routes);
      await care.setPetPhoto('miso', sampleJpeg(64, 64));
      await care.syncPetPhotos();
      expect(adapter.count('PUT /v1/pets/miso/photo'), 2);
      expect(care.petById('miso').photoSync, PhotoSync.none);

      routes['POST /v1/pets/miso/photo/upload']!
        ..clear()
        ..add(const Answer(404, {'error': 'That pet was removed.'}));
      await care.setPetPhoto('miso', sampleJpeg(80, 80));
      await care.syncPetPhotos();
      expect(care.petById('miso').photoSync, PhotoSync.none);
      expect(care.petById('miso').hasPhoto, isTrue); // local photo kept
    },
  );

  test('cache hit for an unchanged key, new download for a new key', () async {
    const k1 = 'households/h/pets/miso/k1.jpg';
    const k2 = 'households/h/pets/miso/k2.jpg';
    final (care, adapter, transfer) = await connectedCare(
      dir,
      snapshot: snapshotWithPhoto(photoKey: k1, photoUrl: 'https://b/k1'),
    );
    expect(transfer.gets, ['https://b/k1']);
    expect(AppLog.logged('pet.photo_downloaded'), isTrue);
    final firstPath = care.petById('miso').photoPath!;
    expect(firstPath, contains('pet_photo_cache'));
    expect(File(firstPath).existsSync(), isTrue);

    // Same key, fresh URL: no refetch.
    adapter.routes['GET /v1/household'] = [
      Answer(200, snapshotWithPhoto(photoKey: k1, photoUrl: 'https://b/k1b')),
    ];
    AppLog.testRecords.clear();
    final again = CareRepository(
      api: routeApi(adapter),
      store: HouseholdStore(),
      photoStore: PetPhotoStore(baseDir: () async => dir),
      photoTransfer: transfer,
    );
    await again.restore();
    await again.sync(force: true);
    expect(transfer.gets, hasLength(1));
    expect(AppLog.logged('pet.photo_cache_hit'), isTrue);
    expect(again.petById('miso').photoPath, firstPath);

    // New key (someone changed it): one download, old file pruned.
    adapter.routes['GET /v1/household'] = [
      Answer(200, snapshotWithPhoto(photoKey: k2, photoUrl: 'https://b/k2')),
    ];
    await again.sync(force: true);
    expect(transfer.gets.last, 'https://b/k2');
    expect(File(firstPath).existsSync(), isFalse);

    // Cache file deleted behind our back → silently downloaded again.
    await File(again.petById('miso').photoPath!).delete();
    await again.sync(force: true);
    expect(transfer.gets, hasLength(3));
  });

  test('expired download URL → one household refetch, then download', () async {
    const key = 'households/h/pets/miso/x1.jpg';
    final adapter = RouteAdapter({
      'GET /v1/household': [
        Answer(
          200,
          snapshotWithPhoto(photoKey: key, photoUrl: 'https://b/old'),
        ),
        Answer(
          200,
          snapshotWithPhoto(photoKey: key, photoUrl: 'https://b/new'),
        ),
      ],
    });
    final transfer = FakeTransfer()
      ..getFailures.add(const PhotoTransferException('rejected', 403));
    final care = CareRepository(
      api: routeApi(adapter),
      store: HouseholdStore(),
      photoStore: PetPhotoStore(baseDir: () async => dir),
      photoTransfer: transfer,
    );
    await care.restore();
    await care.sync(force: true);
    expect(transfer.gets, ['https://b/old', 'https://b/new']);
    expect(care.petById('miso').hasPhoto, isTrue);
  });

  test(
    'another phone sets a newer photo → ours is replaced by theirs',
    () async {
      const mine = 'households/h/pets/miso/mine.jpg';
      final (care, adapter, transfer) = await connectedCare(
        dir,
        routes: uploadRoutes(mine),
      );
      await care.setPetPhoto('miso', sampleJpeg(64, 64));
      await care.syncPetPhotos();
      final ownPath = care.petById('miso').photoPath!;
      expect(File(ownPath).existsSync(), isTrue);

      adapter.routes['GET /v1/household'] = [
        Answer(
          200,
          snapshotWithPhoto(
            photoKey: 'households/h/pets/miso/theirs.jpg',
            photoUrl: 'https://b/theirs',
          ),
        ),
      ];
      await care.sync(force: true);
      final pet = care.petById('miso');
      expect(pet.photoVersion, 0);
      expect(pet.photoPath, contains('pet_photo_cache'));
      expect(transfer.gets.last, 'https://b/theirs');
      await Future<void>.delayed(Duration.zero);
      expect(File(ownPath).existsSync(), isFalse);
    },
  );

  test('remove photo deletes the file and the server copy', () async {
    final (care, adapter, _) = await connectedCare(
      dir,
      routes: uploadRoutes('households/h/pets/miso/d1.jpg'),
    );
    await care.setPetPhoto('miso', sampleJpeg(64, 64));
    await care.syncPetPhotos();
    final path = care.petById('miso').photoPath!;

    expect(await care.removePetPhoto('miso'), isTrue);
    await care.syncPetPhotos();
    final pet = care.petById('miso');
    expect(pet.hasPhoto, isFalse);
    expect(pet.photoKey, isNull);
    expect(pet.photoSync, PhotoSync.none);
    expect(File(path).existsSync(), isFalse);
    expect(adapter.count('DELETE /v1/pets/miso/photo'), 1);
    expect(AppLog.logged('pet.photo_removed'), isTrue);
  });

  test('photo logs carry ids only, never pet names', () async {
    final (care, _, _) = await connectedCare(
      dir,
      routes: uploadRoutes('households/h/pets/miso/n1.jpg'),
    );
    await care.setPetPhoto('miso', sampleJpeg(64, 64));
    await care.syncPetPhotos();
    for (final record in AppLog.testRecords.where(
      (r) => r.name.startsWith('pet.photo'),
    )) {
      expect('${record.fields}'.contains('Miso'), isFalse, reason: record.name);
    }
  });

  test('a log by someone no longer in the household reads "Former member"', () {
    final care = sampleCare();
    expect(care.memberById('gone-1').name, CareRepository.formerMemberName);
    expect(
      HouseholdException('x', kind: HouseholdErrorKind.offline).timedOut,
      isFalse,
    );
  });
}
