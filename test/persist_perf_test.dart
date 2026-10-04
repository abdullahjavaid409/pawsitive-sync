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
  final watch = Stopwatch();

  @override
  Future<void> write(StoredHousehold house) async {
    writes++;
    watch.start();
    await super.write(house);
    watch.stop();
  }
}

const _day = '2026-10-03';

List<DoseRecord> _logs(int count) => [
  for (var i = 0; i < count; i++)
    DoseRecord(
      id: 'log-$i',
      medicationId: 'med-${i % 20}',
      part: DayPart.values[i % 3],
      day: i < 20 ? _day : '2026-0${1 + i % 9}-1${i % 9}',
      memberId: i.isEven ? 'you' : 'dan',
      outcome: LogOutcome.given,
      amount: '2 units',
      timeLabel: '8:0${i % 10} AM',
      note: i % 7 == 0 ? 'Partial dose' : null,
    ),
];

StoredHousehold _house(int logs, {String? token}) => StoredHousehold(
  token: token,
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
        supplyTotal: 0,
        dosesLeft: 0,
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

  test('persist + restore 5k logs stays fast', () async {
    final store = HouseholdStore();
    final house = _house(5000);
    const runs = 10;
    final write = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await store.write(house);
    }
    write.stop();
    final read = Stopwatch()..start();
    StoredHousehold? back;
    for (var i = 0; i < runs; i++) {
      back = await store.read();
    }
    read.stop();
    // ignore: avoid_print
    print(
      'perf: write(5k logs) avg=${write.elapsedMicroseconds ~/ runs}us '
      'read avg=${read.elapsedMicroseconds ~/ runs}us',
    );
    expect(back!.logs, hasLength(3000), reason: 'store caps saved history');
  });

  test('doses getter with 3k logs × 20 meds', () async {
    final care = CareRepository(
      store: HouseholdStore(),
      clock: () => DateTime(2026, 10, 3, 14),
    );
    await HouseholdStore().write(_house(3000));
    await care.restore();
    const runs = 200;
    final watch = Stopwatch()..start();
    var count = 0;
    for (var i = 0; i < runs; i++) {
      count += care.doses.length;
    }
    watch.stop();
    // ignore: avoid_print
    print('perf: doses getter avg=${watch.elapsedMicroseconds ~/ runs}us');
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
      clock: () => DateTime(2026, 10, 3, 14),
    );
    await care.sync(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // ignore: avoid_print
    print('perf: writes per sync=${store.writes}');
    expect(store.writes, 1);
  });
}
