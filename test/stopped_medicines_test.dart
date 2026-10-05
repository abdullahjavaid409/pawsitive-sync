import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/sync_engine.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/data/vet_report_pdf.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';

DateTime _clock() => DateTime(2026, 10, 3, 14);

Map<String, Object?> _log(
  String id,
  String medicationId,
  String day, {
  String outcome = 'given',
  String part = 'morning',
}) => {
  'id': id,
  'medicationId': medicationId,
  'part': part,
  'day': day,
  'memberId': 'owner',
  'outcome': outcome,
  'amount': '50 mg',
  'timeLabel': '8:00 AM',
};

/// A two-pet household where the antibiotic was stopped on Oct 2, before
/// this phone joined. [archived] false = an old server without the list.
Map<String, Object?> _household({
  bool archived = true,
  List<Map<String, Object?>>? logs,
}) {
  final body = connectHouseholdBody(memberId: 'me');
  return {
    ...body,
    'members': [
      {'id': 'owner', 'name': 'Sam', 'role': 'owner'},
      {'id': 'me', 'name': 'Me', 'role': 'caregiver', 'isYou': true},
    ],
    'pets': [
      {'id': 'miso', 'name': 'Miso', 'species': 'cat'},
      {'id': 'rex', 'name': 'Rex', 'species': 'dog'},
    ],
    'archivedMedications': [
      if (archived)
        {
          'id': 'abx',
          'petId': 'miso',
          'name': 'Antibiotic',
          'amount': '50 mg',
          'parts': ['morning'],
          'supplyTotal': 0,
          'dosesLeft': 0,
          'startDay': '2026-09-25',
          'endDay': '',
          'archivedAt': '2026-10-02T09:30:00.000Z',
        },
    ],
    'logs':
        logs ??
        [
          _log('l1', 'abx', '2026-10-01'),
          _log('l2', 'abx', '2026-09-30'),
          _log('l3', 'insulin', '2026-10-03'),
        ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  Future<CareRepository> joined([Map<String, Object?>? body]) async {
    final care = CareRepository(
      api: fakeHouseholdApi(
        FakeHouseholdAdapter([(200, body ?? _household())]),
      ),
      store: HouseholdStore(),
      clock: _clock,
    );
    expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
    return care;
  }

  test('a joining phone sees the stopped medicine by name in the report '
      '(two pets, no placeholder)', () async {
    final care = await joined();
    final line = care
        .reportFor('miso', 7)
        .lines
        .singleWhere((l) => l.medication.id == 'abx');
    expect(line.removed, isTrue);
    expect(line.given, 2);
    expect(line.medication.name, 'Antibiotic');
    expect(line.medication.historyName, 'Antibiotic (stopped Oct 2)');
    expect(
      care.reportFor('miso', 7).recent.map((e) => e.medicationName),
      contains('Antibiotic (stopped Oct 2)'),
    );
    // The other pet’s report doesn’t borrow it.
    expect(care.reportFor('rex', 7).lines, isEmpty);
    expect(
      care.activity.map((a) => a.emphasis),
      contains('Antibiotic (stopped Oct 2) · 50 mg'),
    );
    // The PDF uses the same label.
    final pdf = await buildVetReportPdf(
      pet: care.petById('miso'),
      report: care.reportFor('miso', 7),
      showCaregivers: true,
      generatedAt: care.now,
      fonts: await VetReportFonts.load(),
    );
    expect(pdf.bytes, isNotEmpty);

    // Survives a restart.
    await care.flushPersist();
    final again = CareRepository(store: HouseholdStore(), clock: _clock);
    await again.restore();
    expect(
      again
          .reportFor('miso', 7)
          .lines
          .singleWhere((l) => l.removed)
          .medication
          .historyName,
      'Antibiotic (stopped Oct 2)',
    );
  });

  test('stopped medicines never reach Today, schedules or reminders', () async {
    final care = await joined();
    expect(care.medications.map((m) => m.id), ['insulin']);
    expect(care.medicationsFor('miso').map((m) => m.id), ['insulin']);
    expect(care.doses.map((d) => d.medicationId), everyElement('insulin'));
    expect(care.nextDue?.medicationId, anyOf(isNull, 'insulin'));
    expect(care.medicationById('abx'), isNull);
    // Logging against it is refused (it’s not on the schedule).
    expect(
      await care.logDose(
        doseId: 'abx.morning',
        memberId: 'me',
        amount: '',
        timeLabel: '8:00 AM',
      ),
      isFalse,
    );
    // Still archived after a reload.
    await care.flushPersist();
    final saved = await HouseholdStore().read();
    expect(saved!.medications.map((m) => m.id), ['insulin']);
    expect(saved.archivedMedications.single.id, 'abx');
  });

  test('without the server list, unknown history is left out — never a '
      '"Removed medicine" placeholder', () async {
    final care = await joined(_household(archived: false));
    final names = care.reportFor('miso', 7).lines.map((l) => l.medication.name);
    expect(names, isNot(contains('Removed medicine')));
    expect(names, ['Insulin']);
  });

  test(
    'a medicine stopped on this phone is archived with its stop time',
    () async {
      final care = CareRepository(store: HouseholdStore(), clock: _clock);
      final petId = (await care.addPet(name: 'Miso', species: Species.cat))!;
      await care.addMedication(
        petId: petId,
        name: 'Antibiotic',
        amount: '50 mg',
        parts: const [DayPart.morning],
      );
      final id = care.medications.single.id;
      await care.logDose(
        doseId: '$id.morning',
        memberId: 'you',
        amount: '',
        timeLabel: '8:00 AM',
      );
      await care.removeMedication(id);
      expect(care.medications, isEmpty);
      expect(care.doses, isEmpty);
      expect(
        care.activity.single.emphasis,
        'Antibiotic (stopped Oct 3) · 50 mg',
      );
      await care.flushPersist();
      final saved = (await HouseholdStore().read())!;
      final stopped = saved.archivedMedications.single;
      expect(stopped.archivedAt, isNotNull);
      expect(stopped.endDay, '2026-10-03');
      expect(saved.logs, hasLength(1), reason: 'history stays');
    },
  );

  test(
    'a medicine re-added on the server is active again, not archived',
    () async {
      final body = _household();
      body['medications'] = [
        ...(body['medications']! as List),
        {
          'id': 'abx',
          'petId': 'miso',
          'name': 'Antibiotic',
          'amount': '50 mg',
          'parts': ['morning'],
          'supplyTotal': 0,
          'dosesLeft': 0,
          'startDay': '2026-10-03',
        },
      ];
      body['archivedMedications'] = const [];
      final care = await joined(_household());
      expect(care.medicationById('abx'), isNull);
      final sync = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([(200, body)]),
          token: 'house-token',
        ),
        store: HouseholdStore(),
        clock: _clock,
      );
      await sync.restore();
      await sync.sync(force: true);
      expect(sync.medicationById('abx'), isNotNull);
      expect(sync.reportFor('miso', 7).lines.where((l) => l.removed), isEmpty);
    },
  );

  group('Snapshot merge on disk', () {
    test('a "not sure" resolved on another phone is deleted here too; older '
        'history and queued offline doses stay', () async {
      final outbox = SyncOutbox();
      final store = HouseholdStore();
      final api = fakeHouseholdApi(
        FakeHouseholdAdapter([
          (
            200,
            _household(
              logs: [
                _log('unsure', 'insulin', '2026-10-03', outcome: 'uncertain'),
              ],
            ),
          ),
        ]),
      );
      final care = CareRepository(
        api: api,
        store: store,
        syncEngine: SyncEngine(outbox: outbox),
        clock: _clock,
      );
      await care.join(code: 'ABC234', name: 'Me');
      await care.flushPersist();
      // Something older than the server’s window, saved earlier on this phone.
      await store.write(
        StoredHousehold(
          token: 'house-token',
          memberId: 'me',
          inviteCode: 'ABC234',
          isPro: true,
          plan: BillingPlan.yearly,
          members: care.members,
          pets: care.pets,
          medications: care.medications,
          logs: [
            ...care.logs,
            const DoseRecord(
              id: 'ancient',
              medicationId: 'insulin',
              part: DayPart.morning,
              day: '2026-03-01',
              memberId: 'owner',
              outcome: LogOutcome.given,
              amount: '',
              timeLabel: '8:00 AM',
            ),
          ],
        ),
      );
      // A dose queued offline that the server hasn’t received yet.
      const queued = DoseRecord(
        id: 'queued',
        medicationId: 'insulin',
        part: DayPart.evening,
        day: '2026-10-03',
        memberId: 'me',
        outcome: LogOutcome.given,
        amount: '',
        timeLabel: '1:30 PM',
      );
      await outbox.enqueue(
        SyncBatchOp(id: 'op-q', type: 'logDose', payload: queued.toJson()),
      );
      await store.write(
        StoredHousehold(
          token: 'house-token',
          memberId: 'me',
          inviteCode: 'ABC234',
          isPro: true,
          plan: BillingPlan.yearly,
          members: care.members,
          pets: care.pets,
          medications: care.medications,
          logs: [queued, ...care.logs],
        ),
      );

      final relaunched = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            // The batch fails on the server; the fetch still works.
            (500, {'error': 'boom'}),
            (200, _household(logs: [_log('given', 'insulin', '2026-10-03')])),
          ]),
          token: 'house-token',
        ),
        store: HouseholdStore(),
        syncEngine: SyncEngine(outbox: outbox),
        clock: _clock,
      );
      await relaunched.restore();
      expect(relaunched.logs.map((l) => l.id), isNot(contains('ancient')));
      await relaunched.sync(force: true);
      await relaunched.flushPersist();

      final onDisk = {for (final l in await HouseholdStore().readLogs()) l.id};
      expect(onDisk, containsAll(['given', 'ancient', 'queued']));
      expect(onDisk, isNot(contains('unsure')));
      expect(
        relaunched.logs.map((l) => l.id),
        containsAll(['given', 'queued']),
      );
      expect(relaunched.logs.map((l) => l.id), isNot(contains('unsure')));
    });

    test('joining another household drops this phone’s old history', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([(200, _household())])),
        store: HouseholdStore(),
        clock: _clock,
      );
      final petId = (await care.addPet(name: 'Solo', species: Species.cat))!;
      await care.addMedication(
        petId: petId,
        name: 'Old med',
        amount: '',
        parts: const [DayPart.morning],
      );
      await care.logDose(
        doseId: '${care.medications.single.id}.morning',
        memberId: 'you',
        amount: '',
        timeLabel: '8:00 AM',
      );
      await care.flushPersist();
      expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
      await care.flushPersist();
      final ids = {for (final l in await HouseholdStore().readLogs()) l.id};
      expect(ids, {'l1', 'l2', 'l3'});
    });
  });
}
