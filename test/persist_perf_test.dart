import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';

/// Counts writes so we can prove bursts of changes are coalesced.
class _CountingStore extends HouseholdStore {
  int writes = 0;

  @override
  Future<void> write(StoredHousehold house) async {
    writes++;
    await super.write(house);
  }
}

/// Timings print only with `PERF=1 flutter test test/persist_perf_test.dart`.
void _report(String line) {
  // ignore: avoid_print
  if (Platform.environment['PERF'] == '1') print('perf: $line');
}

final _clock = DateTime(2026, 10, 3, 14);

/// [count] logs over the last 90 days (all inside the window loaded at
/// launch: the worst case for restore).
List<DoseRecord> _logs(int count) => [
  for (var i = 0; i < count; i++)
    DoseRecord(
      id: 'log-$i',
      medicationId: 'med-${i % 20}',
      part: DayPart.values[i % 3],
      day: dayKey(_clock.subtract(Duration(days: 1 + i % 90))),
      memberId: i.isEven ? 'you' : 'dan',
      outcome: LogOutcome.given,
      amount: '2 units',
      timeLabel: '8:0${i % 10} AM',
      note: i % 7 == 0 ? 'Partial dose' : null,
    ),
];

StoredHousehold _house(int logs) => StoredHousehold(
  token: null,
  memberId: 'you',
  inviteCode: 'ABC234',
  isPro: false,
  plan: BillingPlan.yearly,
  members: const [
    Member(
      id: 'you',
      name: 'You',
      initials: 'You',
      role: MemberRole.owner,
      avatarTone: AvatarTone.brand,
      isYou: true,
    ),
  ],
  pets: const [
    Pet(
      id: 'miso',
      name: 'Miso',
      species: Species.cat,
      ageYears: 3,
      breed: '',
      sex: '',
      conditions: [],
      weightKg: 4,
      onTimePercent: 0,
      dailyMeds: 0,
    ),
  ],
  medications: [
    for (var i = 0; i < 20; i++)
      Medication(
        id: 'med-$i',
        petId: 'miso',
        name: 'Med $i',
        amount: '1 mg',
        parts: DayPart.values,
        supplyTotal: 30,
        dosesLeft: 30,
        startDay: '2026-01-01',
      ),
  ],
  logs: _logs(logs),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  test('5k logs: launch restore, then one dose log writes one row', () async {
    await HouseholdStore().write(_house(5000));
    const runs = 10;
    var restoreUs = 0;
    var historyUs = 0;
    var writeUs = 0;
    for (var run = 0; run < runs; run++) {
      final store = HouseholdStore();
      final care = CareRepository(store: store, clock: () => _clock);
      final restore = Stopwatch()..start();
      await care.restore(); // before the first frame: last 14 days
      restoreUs += restore.elapsedMicroseconds;
      expect(care.logs.length, lessThan(1000));
      final history = Stopwatch()..start();
      await care.loadRecentHistory(); // right after it
      historyUs += history.elapsedMicroseconds;
      expect(care.logs.length, 5000 + run);

      final write = Stopwatch()..start();
      expect(
        await care.logDose(
          doseId: 'med-$run.morning',
          memberId: 'you',
          amount: '',
          timeLabel: '2:00 PM',
        ),
        isTrue,
      );
      await care.flushPersist();
      writeUs += write.elapsedMicroseconds;
      // The new log row + the medicine's supply count. Nothing else.
      expect(store.lastWriteRows, 2);
    }
    _report(
      'first-frame restore(5k logs) avg=${restoreUs ~/ runs}us '
      'rest of history avg=${historyUs ~/ runs}us '
      'dose-log write avg=${writeUs ~/ runs}us',
    );
  });

  test('doses getter with 3k logs × 20 meds', () async {
    final care = CareRepository(store: HouseholdStore(), clock: () => _clock);
    await HouseholdStore().write(_house(3000));
    await care.restore();
    await care.loadRecentHistory();
    const runs = 200;
    final watch = Stopwatch()..start();
    var count = 0;
    for (var i = 0; i < runs; i++) {
      count += care.doses.length;
    }
    watch.stop();
    _report('doses getter avg=${watch.elapsedMicroseconds ~/ runs}us');
    expect(count, greaterThan(0));
  });

  test('one sync writes the household to disk once', () async {
    final store = _CountingStore();
    final care = CareRepository(
      api: fakeHouseholdApi(
        FakeHouseholdAdapter([(200, connectHouseholdBody())]),
        token: 'house-token',
      ),
      store: store,
      clock: () => _clock,
    );
    await care.sync(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _report('writes per sync=${store.writes}');
    expect(store.writes, 1);
  });
}
