import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sample_household.dart';
import 'test_log_helpers.dart';

/// Magic Patterns v14 fields: medicine repeat, with food and site; pet
/// household note and weigh-ins.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  Medication med({int everyDays = 1, String start = '2026-10-01'}) =>
      Medication(
        id: 'm',
        petId: 'p',
        name: 'Drops',
        amount: '1 drop',
        parts: const [DayPart.morning],
        supplyTotal: 10,
        dosesLeft: 10,
        startDay: start,
        everyDays: everyDays,
      );

  group('repeat', () {
    test('every day, every 2 days and weekly count from the start day', () {
      expect(med().isActiveOn('2026-10-02'), isTrue);
      final alt = med(everyDays: 2);
      expect(alt.isActiveOn('2026-10-01'), isTrue);
      expect(alt.isActiveOn('2026-10-02'), isFalse);
      expect(alt.isActiveOn('2026-10-03'), isTrue);
      expect(alt.isActiveOn('2026-09-29'), isFalse, reason: 'before start');
      final weekly = med(everyDays: 7);
      expect(weekly.isActiveOn('2026-10-08'), isTrue);
      expect(weekly.isActiveOn('2026-10-09'), isFalse);
      expect(weekly.repeatLabel, 'Thursdays');
    });

    test('across a DST change the count stays whole days', () {
      final alt = med(everyDays: 2, start: '2026-10-24');
      // Europe/US DST ends late Oct / early Nov.
      expect(alt.isActiveOn('2026-11-01'), isTrue);
      expect(alt.isActiveOn('2026-11-02'), isFalse);
    });

    test('junk repeat values read as every day (never skip a dose)', () {
      for (final raw in [3, 0, -1, '2', null]) {
        final parsed = medicationFromJson({
          ...med().toJson(),
          'everyDays': raw,
        });
        expect(parsed.everyDays, 1, reason: '$raw');
      }
      expect(
        medicationFromJson({...med().toJson(), 'everyDays': 7}).everyDays,
        7,
      );
    });

    test('supply estimate spreads over the repeat', () {
      expect(med(everyDays: 2).lastsUntil(DateTime(2026, 10, 1)), isNotEmpty);
      // 10 doses, one a day every 2 days → 20 days.
      expect(
        med(everyDays: 2).lastsUntil(DateTime(2026, 10, 1)),
        'Wed, Oct 21',
      );
    });

    test('detail reads repeat, site and food', () {
      final m = Medication(
        id: 'm',
        petId: 'p',
        name: 'Drops',
        amount: '2 drops',
        parts: const [DayPart.morning, DayPart.evening],
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: '2026-10-01',
        everyDays: 2,
        withFood: true,
        site: 'Left eye',
      );
      expect(
        m.detail,
        '2 drops · Left eye · Every 2 days · morning & evening · with food',
      );
      final back = medicationFromJson(m.toJson());
      expect(back.withFood, isTrue);
      expect(back.site, 'Left eye');
      expect(back.everyDays, 2);
    });
  });

  group('repository', () {
    test('addMedication saves repeat, food, site and a weekly start', () async {
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 9))
        ..debugStorePro = true;
      final ok = await care.addMedication(
        petId: 'juniper',
        name: 'Ear drops',
        amount: '2 drops',
        parts: const [DayPart.morning],
        everyDays: 7,
        withFood: true,
        site: 'Ears',
        startDay: '2026-10-05',
      );
      expect(ok, isTrue);
      final saved = care.medications.singleWhere((m) => m.name == 'Ear drops');
      expect(saved.everyDays, 7);
      expect(saved.startDay, '2026-10-05');
      expect(saved.site, 'Ears');
      expect(saved.withFood, isTrue);
      // Not today (Saturday): no dose on Today.
      expect(care.doses.where((d) => d.medicationId == saved.id), isEmpty);
      expectLogged('medication.add.completed');
    });

    test('a start day in the past is clamped to today', () async {
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 9))
        ..debugStorePro = true;
      await care.addMedication(
        petId: 'juniper',
        name: 'Late',
        amount: '',
        parts: const [DayPart.morning],
        startDay: '2026-01-01',
      );
      expect(
        care.medications.singleWhere((m) => m.name == 'Late').startDay,
        '2026-10-03',
      );
    });

    test(
      'weight changes add a dated weigh-in, one per day, newest 24',
      () async {
        var now = DateTime(2026, 10, 3, 9);
        final care = sampleCare(clock: () => now);
        final pet = care.tryPetById('miso')!;
        Future<void> weigh(double kg) => care.updatePet(
          petId: 'miso',
          name: pet.name,
          species: pet.species,
          ageYears: pet.ageYears,
          weightKg: kg,
        );
        await weigh(4.4);
        await weigh(4.3); // same day: replaces
        expect(care.tryPetById('miso')!.weights, [
          const WeightEntry(day: '2026-10-03', kg: 4.3),
        ]);
        for (var i = 1; i <= 30; i++) {
          now = DateTime(2026, 10, 3 + i, 9);
          await weigh(4 + i / 100);
        }
        final weights = care.tryPetById('miso')!.weights;
        expect(weights, hasLength(Pet.maxWeights));
        expect(weights.last.kg, 4.3);
        expect(weights.first.day.compareTo(weights.last.day), lessThan(0));
      },
    );

    test('household note: signed, dated, cleared, length-checked', () async {
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 9));
      expect(await care.setCareNote('miso', '  Only after she eats  '), isTrue);
      var pet = care.tryPetById('miso')!;
      expect(pet.careNote, 'Only after she eats');
      expect(pet.careNoteBy, care.you.id);
      expect(pet.careNoteDay, '2026-10-03');
      expect(await care.setCareNote('miso', 'x' * 281), isFalse);
      expect(care.lastError, contains('280'));
      expect(await care.setCareNote('miso', ''), isTrue);
      pet = care.tryPetById('miso')!;
      expect(pet.careNote, isEmpty);
      expect(pet.careNoteBy, isEmpty);
      expect(await care.setCareNote('gone', 'x'), isFalse);
    });

    test('profile edits never send the note; note edits do', () {
      const pet = Pet(
        id: 'p',
        name: 'Miso',
        species: Species.cat,
        ageYears: 1,
        breed: '',
        sex: '',
        conditions: [],
        weightKg: 4,
        onTimePercent: 0,
        dailyMeds: 0,
        careNote: 'Note',
      );
      expect(pet.toJson().containsKey('careNote'), isFalse);
      expect(pet.toJson(withNote: true)['careNote'], 'Note');
    });

    test('junk weigh-ins are dropped, not fatal', () {
      final pet = petFromJson({
        'id': 'p',
        'name': 'Miso',
        'species': 'cat',
        'weights': [
          {'day': '2026-10-01', 'kg': 4.2},
          {'day': 'yesterday', 'kg': 4},
          {'day': '2026-10-02', 'kg': -1},
          'junk',
        ],
      });
      expect(pet.weights, [const WeightEntry(day: '2026-10-01', kg: 4.2)]);
    });
  });

  group('SQLite', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pawsitive_v14_');
      path = '${dir.path}/${LocalDatabase.fileName}';
    });

    tearDown(() async {
      await LocalDatabase.shared.close();
      dir.deleteSync(recursive: true);
    });

    test('a v3 file gains the v14 columns; rows round-trip', () async {
      final v3 = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await db.execute('''
              CREATE TABLE pets (
                id TEXT PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
                species TEXT NOT NULL, age_years INTEGER NOT NULL,
                weight_kg REAL NOT NULL, breed TEXT NOT NULL, sex TEXT NOT NULL,
                conditions TEXT NOT NULL, photo_key TEXT,
                photo_version INTEGER NOT NULL, photo_sync TEXT NOT NULL)''');
            await db.execute('''
              CREATE TABLE medications (
                id TEXT PRIMARY KEY, position INTEGER NOT NULL, pet_id TEXT NOT NULL,
                name TEXT NOT NULL, amount TEXT NOT NULL, parts TEXT NOT NULL,
                supply_total INTEGER NOT NULL, doses_left INTEGER NOT NULL,
                start_day TEXT NOT NULL, end_day TEXT NOT NULL,
                archived INTEGER NOT NULL, archived_at TEXT, times TEXT,
                needs_pro INTEGER NOT NULL DEFAULT 0)''');
          },
        ),
      );
      await v3.insert('medications', {
        'id': 'insulin',
        'position': 0,
        'pet_id': 'miso',
        'name': 'Insulin',
        'amount': '2 u',
        'parts': 'morning',
        'supply_total': 0,
        'doses_left': 0,
        'start_day': '2026-01-01',
        'end_day': '',
        'archived': 0,
      });
      await v3.insert('pets', {
        'id': 'miso',
        'position': 0,
        'name': 'Miso',
        'species': 'cat',
        'age_years': 4,
        'weight_kg': 4.2,
        'breed': '',
        'sex': '',
        'conditions': '[]',
        'photo_version': 0,
        'photo_sync': 'none',
      });
      await v3.close();

      LocalDatabase.shared = LocalDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: () async => path,
      );
      final db = (await LocalDatabase.shared.open())!;
      expectLogged('store.migrated', fields: {'from': 3, 'to': 4});
      final old = LocalRows.toMedication(
        (await db.query('medications')).single,
      );
      expect(old.everyDays, 1);
      expect(old.withFood, isFalse);
      final oldPet = LocalRows.toPet((await db.query('pets')).single);
      expect(oldPet.careNote, isEmpty);
      expect(oldPet.weights, isEmpty);

      final medRow = LocalRows.medication(
        Medication(
          id: 'insulin',
          petId: 'miso',
          name: 'Insulin',
          amount: '2 u',
          parts: const [DayPart.morning],
          supplyTotal: 0,
          dosesLeft: 0,
          startDay: '2026-01-01',
          everyDays: 2,
          withFood: true,
          site: 'Skin',
        ),
        0,
      );
      await db.update('medications', medRow);
      final med = LocalRows.toMedication(
        (await db.query('medications')).single,
      );
      expect((med.everyDays, med.withFood, med.site), (2, true, 'Skin'));

      await db.update(
        'pets',
        LocalRows.pet(
          oldPet.copyWith(
            careNote: 'Only after food',
            careNoteBy: 'you',
            careNoteDay: '2026-10-03',
            weights: const [WeightEntry(day: '2026-10-03', kg: 4.2)],
          ),
          0,
        ),
      );
      final pet = LocalRows.toPet((await db.query('pets')).single);
      expect(pet.careNote, 'Only after food');
      expect(pet.weights.single.kg, 4.2);
    });
  });
}
