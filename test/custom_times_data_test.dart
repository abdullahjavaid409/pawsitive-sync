import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/data/vet_report_pdf.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

DateTime _clock() => DateTime(2026, 10, 4, 9);

const _insulinTimes = {DayPart.morning: 7 * 60, DayPart.evening: 19 * 60};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  group('wire format', () {
    test('junk times from a server are dropped (defaults) and logged once', () {
      Map<String, Object?> json(Object? times) => {
        'id': 'junk-med',
        'petId': 'p',
        'name': 'X',
        'parts': ['morning', 'evening'],
        'startDay': '2026-10-04',
        'times': times,
      };
      final med = medicationFromJson(
        json({'morning': '7am', 'evening': '19:00'}),
      );
      expect(med.times, {DayPart.evening: 19 * 60}, reason: 'valid part kept');
      medicationFromJson(json(['bad']));
      expect(
        AppLog.testRecords.where((r) => r.name == 'medication.times_ignored'),
        hasLength(1),
      );
      // Unknown parts (a newer server) are not junk.
      medicationFromJson({
        ...json({'night': '23:00'}),
        'id': 'future-med',
      });
      expect(
        AppLog.testRecords.where((r) => r.name == 'medication.times_ignored'),
        hasLength(1),
      );
    });

    test(
      'toJson omits times when unset (old servers), sends HH:mm when set',
      () {
        const plain = Medication(
          id: 'm',
          petId: 'p',
          name: 'X',
          amount: '',
          parts: [DayPart.morning],
          supplyTotal: 0,
          dosesLeft: 0,
          startDay: '2026-10-04',
        );
        expect(plain.toJson().containsKey('times'), isFalse);
        final timed = plain.copyWith(times: {DayPart.morning: 7 * 60 + 5});
        expect(timed.toJson()['times'], {'morning': '07:05'});
        expect(DoseTimes.encode({DayPart.evening: 23 * 60 + 59}), {
          'evening': '23:59',
        });
        // Defaults and parts that aren’t selected are not stored.
        expect(
          DoseTimes.normalize(
            {DayPart.morning: 8 * 60, DayPart.evening: 19 * 60},
            [DayPart.morning],
          ),
          isEmpty,
        );
      },
    );
  });

  group('repository', () {
    Future<CareRepository> solo() async {
      final care = CareRepository(store: HouseholdStore(), clock: _clock);
      await care.addPet(name: 'Miso', species: Species.cat);
      return care;
    }

    test('add with times; saved in SQLite and back after a relaunch', () async {
      // Pro: Free schedules the morning dose only.
      final care = await solo()
        ..debugStorePro = true;
      final pet = care.pets.single;
      expect(
        await care.addMedication(
          petId: pet.id,
          name: 'Insulin',
          amount: '2 u',
          parts: [DayPart.morning, DayPart.evening],
          times: _insulinTimes,
        ),
        isTrue,
      );
      expectLogged('medication.add.completed', fields: {'customTimes': 2});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final again = CareRepository(store: HouseholdStore(), clock: _clock);
      await again.restore();
      final med = again.medications.single;
      expect(med.times, _insulinTimes);
      expect(med.timeLabelFor(DayPart.evening), '7:00 PM');
    });

    test(
      'change times offline on a shared phone: one times-only op queued',
      () async {
        final adapter = FakeHouseholdAdapter([(200, connectHouseholdBody())]);
        final care = CareRepository(
          api: fakeHouseholdApi(adapter),
          store: HouseholdStore(),
          clock: _clock,
        );
        expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        adapter.replies
          ..clear()
          ..add((0, 'offline'));
        expect(
          await care.setMedicationTimes('insulin', {DayPart.morning: 7 * 60}),
          isTrue,
        );
        expect(
          care.medicationById('insulin')!.minuteFor(DayPart.morning),
          7 * 60,
        );
        expectLogged(
          'medication.times.completed',
          fields: {'offline': true, 'queued': true},
        );
        final ops = await SyncOutbox().read();
        final op = ops.singleWhere((o) => o.type == 'updateMedication');
        expect(op.payload, {
          'id': 'insulin',
          'times': {'morning': '07:00'},
        });
      },
    );

    test(
      'online: PATCH carries only the times; the server answer is kept',
      () async {
        final adapter = FakeHouseholdAdapter([(200, connectHouseholdBody())]);
        final care = CareRepository(
          api: fakeHouseholdApi(adapter),
          store: HouseholdStore(),
          clock: _clock,
        );
        expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        adapter.replies
          ..clear()
          ..add((
            200,
            {
              'medication': {
                'id': 'insulin',
                'petId': 'miso',
                'name': 'Insulin',
                'amount': '2 u',
                'parts': ['morning'],
                'supplyTotal': 30,
                'dosesLeft': 29,
                'startDay': '2026-01-01',
                'times': {'morning': '06:45'},
              },
            },
          ));
        adapter.requests.clear();
        expect(
          await care.setMedicationTimes('insulin', {
            DayPart.morning: 6 * 60 + 45,
          }),
          isTrue,
        );
        final request = adapter.requests.single;
        expect(request.method, 'PATCH');
        expect(request.path, '/v1/medications/insulin');
        expect(request.data, {
          'times': {'morning': '06:45'},
        });
        expect(
          care.medicationById('insulin')!.dosesLeft,
          29,
          reason: 'server copy wins',
        );
      },
    );

    test('same times again is a no-op; a sitter can’t change times', () async {
      final care = await solo();
      await care.addMedication(
        petId: care.pets.single.id,
        name: 'Insulin',
        amount: '',
        parts: [DayPart.morning],
        times: {DayPart.morning: 7 * 60},
      );
      final id = care.medications.single.id;
      expect(
        await care.setMedicationTimes(id, {DayPart.morning: 7 * 60}),
        isTrue,
      );
      expectLogged('medication.times.noop');
      expect(
        await care.setMedicationTimes('missing', {DayPart.morning: 7 * 60}),
        isFalse,
      );
      expect(care.lastError, contains('removed'));

      final body = connectHouseholdBody(memberId: 'me');
      final sitterBody = {
        ...body,
        'members': [
          {'id': 'you', 'name': 'Sam', 'role': 'owner'},
          {'id': 'me', 'name': 'Me', 'role': 'sitter', 'isYou': true},
        ],
      };
      final sitter = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([(200, sitterBody), (200, {})]),
        ),
        store: HouseholdStore(),
        clock: _clock,
      );
      expect(await sitter.join(code: 'ABC234', name: 'Me'), isNull);
      expect(
        await sitter.setMedicationTimes('insulin', {DayPart.morning: 7 * 60}),
        isFalse,
      );
      expectLogged('medication.times.blocked', fields: {'reason': 'role'});
    });

    test(
      'a partner’s snapshot (times kept by the server) shows on this phone',
      () async {
        final body = connectHouseholdBody();
        final meds = [
          {
            ...((body['medications']! as List).single as Map<String, Object?>),
            'times': {'morning': '07:30'},
          },
        ];
        final care = CareRepository(
          api: fakeHouseholdApi(
            FakeHouseholdAdapter([
              (200, {...body, 'medications': meds}),
            ]),
          ),
          store: HouseholdStore(),
          clock: _clock,
        );
        expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
        expect(
          care.medicationById('insulin')!.timeLabelFor(DayPart.morning),
          '7:30 AM',
        );
        expect(care.doseById('insulin.morning')!.timeLabel, '7:30 AM');
      },
    );

    test('vet report names the scheduled time of a missed dose', () async {
      final care = await solo();
      await care.addMedication(
        petId: care.pets.single.id,
        name: 'Insulin',
        amount: '',
        parts: [DayPart.morning],
        times: {DayPart.morning: 7 * 60},
      );
      final report = care.reportFor(care.pets.single.id, 1);
      final missed = report.missedDoses.single;
      expect(missed.timeLabel, '7:00 AM');
      expect(missedDoseLabel(missed), 'Oct 4 · Insulin (morning 7:00 AM)');
      final pdf = await buildVetReportPdf(
        pet: care.pets.single,
        report: report,
        showCaregivers: false,
        generatedAt: care.now,
        fonts: await VetReportFonts.load(),
      );
      expect(pdf.bytes, isNotEmpty);
    });
  });

  group('SQLite v1 → v2', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pawsitive_times_');
      path = '${dir.path}/${LocalDatabase.fileName}';
    });

    tearDown(() async {
      await LocalDatabase.shared.close();
      dir.deleteSync(recursive: true);
    });

    test(
      'an existing v1 file gains the times column; old rows read as defaults',
      () async {
        // The schema phones have today (v1, no times column).
        final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
              );
              await db.execute('''
              CREATE TABLE medications (
                id TEXT PRIMARY KEY, position INTEGER NOT NULL, pet_id TEXT NOT NULL,
                name TEXT NOT NULL, amount TEXT NOT NULL, parts TEXT NOT NULL,
                supply_total INTEGER NOT NULL, doses_left INTEGER NOT NULL,
                start_day TEXT NOT NULL, end_day TEXT NOT NULL,
                archived INTEGER NOT NULL, archived_at TEXT)''');
            },
          ),
        );
        await v1.insert('medications', {
          'id': 'insulin',
          'position': 0,
          'pet_id': 'miso',
          'name': 'Insulin',
          'amount': '2 u',
          'parts': 'morning,evening',
          'supply_total': 0,
          'doses_left': 0,
          'start_day': '2026-01-01',
          'end_day': '',
          'archived': 0,
        });
        await v1.close();

        LocalDatabase.shared = LocalDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: () async => path,
        );
        final db = (await LocalDatabase.shared.open())!;
        expectLogged(
          'store.migrated',
          fields: {'from': 1, 'to': LocalDatabase.schemaVersion},
        );
        final columns = await db.rawQuery('PRAGMA table_info(medications)');
        expect(columns.map((c) => c['name']), contains('times'));
        final row = (await db.query('medications')).single;
        final med = LocalRows.toMedication(row);
        expect(med.times, isEmpty);
        expect(med.minuteFor(DayPart.morning), 8 * 60);
        // A v2 write round-trips; a junk value reads as defaults.
        await db.update(
          'medications',
          LocalRows.medication(
            med.copyWith(times: {DayPart.evening: 19 * 60}),
            0,
          ),
        );
        expect(
          LocalRows.toMedication((await db.query('medications')).single).times,
          {DayPart.evening: 19 * 60},
        );
        await db.update('medications', {'times': 'not json'});
        expect(
          LocalRows.toMedication((await db.query('medications')).single).times,
          isEmpty,
        );
        expectLogged(
          'medication.times_ignored',
          fields: {'medicationId': 'insulin'},
        );
        expect(jsonDecode(jsonEncode(DoseTimes.encode({DayPart.morning: 0}))), {
          'morning': '00:00',
        });
      },
    );
  });
}
