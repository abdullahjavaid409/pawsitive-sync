import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _miso = Pet(
  id: 'miso',
  name: 'Miso',
  species: Species.cat,
  ageYears: 12,
  breed: '',
  sex: '',
  conditions: [],
  weightKg: 4,
  onTimePercent: 100,
  dailyMeds: 1,
);

const _bean = Pet(
  id: 'bean',
  name: 'Bean',
  species: Species.dog,
  ageYears: 3,
  breed: '',
  sex: '',
  conditions: [],
  weightKg: 9,
  onTimePercent: 100,
  dailyMeds: 1,
);

Medication _med(
  String id, {
  String petId = 'miso',
  String name = 'Insulin',
  String amount = '2 units',
  List<DayPart> parts = const [DayPart.morning, DayPart.evening],
  String startDay = '2026-01-01',
  String endDay = '',
  int supplyTotal = 0,
  int dosesLeft = 0,
  Map<DayPart, int> times = const {},
}) => Medication(
  id: id,
  petId: petId,
  name: name,
  amount: amount,
  parts: parts,
  supplyTotal: supplyTotal,
  dosesLeft: dosesLeft,
  startDay: startDay,
  endDay: endDay,
  times: times,
);

DoseRecord _log(
  String medId,
  DayPart part,
  String day, {
  LogOutcome outcome = LogOutcome.given,
  String memberId = 'you',
}) => DoseRecord(
  id: 'log-$medId-${part.name}-$day',
  medicationId: medId,
  part: part,
  day: day,
  memberId: memberId,
  outcome: outcome,
  amount: '',
  timeLabel: '8:02 AM',
);

void main() {
  tzdata.initializeTimeZones();
  final ny = tz.getLocation('America/New_York');

  List<PlannedNotification> plan({
    required DateTime now,
    List<Medication>? meds,
    List<Pet> pets = const [_miso],
    List<DoseRecord> logs = const [],
    ReminderSettings settings = const ReminderSettings(weeklySummary: false),
    tz.Location? location,
    bool shared = false,
    bool isPro = false,
    Set<String> snoozed = const {},
    Map<String, int> refill = const {},
  }) => ReminderPlanner.plan(
    ReminderPlanInput(
      now: now,
      location: location ?? ny,
      pets: pets,
      medications: meds ?? [_med('insulin')],
      logs: logs,
      memberNames: const {'you': 'You', 'dan': 'Dan'},
      settings: settings,
      shared: shared,
      isPro: isPro,
      snoozedKeys: snoozed,
      refillNotifiedAt: refill,
    ),
  );

  // Wall time in New York, as the planner reads it.
  DateTime nyNow(int y, int m, int d, int h, [int min = 0]) =>
      tz.TZDateTime(ny, y, m, d, h, min);

  group('ids', () {
    test('stable per kind + dose + day, distinct otherwise', () {
      final a = ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', '2026-10-04');
      expect(
        ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', '2026-10-04'),
        a,
      );
      final others = {
        ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', '2026-10-05'),
        ReminderIds.forDose(ReminderKind.dose, 'insulin.evening', '2026-10-04'),
        ReminderIds.forDose(ReminderKind.followUp, 'insulin.morning', '2026-10-04'),
        ReminderIds.forDose(ReminderKind.snooze, 'insulin.morning', '2026-10-04'),
      };
      expect(others, hasLength(4));
      expect(others, isNot(contains(a)));
      for (final kind in ReminderKind.values) {
        final id = ReminderIds.of(kind, 'x');
        expect(ReminderIds.kindOf(id), kind);
        expect(id, greaterThan(0));
        expect(id, lessThan(1 << 31), reason: 'fits a 32-bit signed int');
      }
      expect(ReminderIds.kindOf(ReminderIds.legacy), isNull);
    });

    test('payload round-trips and junk decodes to null', () {
      const p = ReminderPayload(
        kind: ReminderKind.followUp,
        doseId: 'insulin.morning',
        day: '2026-10-04',
        at: 42,
        title: 't',
        body: 'b',
      );
      final back = ReminderPayload.decode(p.encode())!;
      expect(back.kind, ReminderKind.followUp);
      expect(back.doseKey, 'insulin.morning|2026-10-04');
      expect(ReminderPayload.decode('{"k":"nope"}'), isNull);
      expect(ReminderPayload.decode('not json'), isNull);
      expect(ReminderPayload.decode(null), isNull);
    });
  });

  group('dose reminders', () {
    test('every due dose for the coming days, nearest first, not just one', () {
      final result = plan(now: nyNow(2026, 10, 4, 7));
      final doses = result.where((n) => n.kind == ReminderKind.dose).toList();
      // 7 days × morning + evening.
      expect(doses, hasLength(14));
      expect(doses.first.when, tz.TZDateTime(ny, 2026, 10, 4, 8));
      expect(doses[1].when, tz.TZDateTime(ny, 2026, 10, 4, 20));
      expect(doses.last.when, tz.TZDateTime(ny, 2026, 10, 10, 20));
      expect({for (final n in result) n.id}, hasLength(result.length));
      for (var i = 1; i < result.length; i++) {
        expect(result[i].when.isBefore(result[i - 1].when), isFalse);
      }
    });

    test('a dose time already past today is not scheduled', () {
      final doses = plan(now: nyNow(2026, 10, 4, 9))
          .where((n) => n.kind == ReminderKind.dose);
      expect(doses.first.when, tz.TZDateTime(ny, 2026, 10, 4, 20));
    });

    test('given or skipped by anyone: no reminder and no follow-up', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 7),
        logs: [
          _log('insulin', DayPart.morning, '2026-10-04', memberId: 'dan'),
          _log('insulin', DayPart.evening, '2026-10-04', outcome: LogOutcome.skipped),
        ],
      );
      expect(result.where((n) => n.day == '2026-10-04'), isEmpty);
    });

    test('"not sure" keeps the reminder but says to check first', () {
      final first = plan(
        now: nyNow(2026, 10, 4, 7),
        logs: [
          _log('insulin', DayPart.morning, '2026-10-04',
              outcome: LogOutcome.uncertain, memberId: 'dan'),
        ],
      ).first;
      expect(first.kind, ReminderKind.dose);
      expect(first.body, 'Dan wasn’t sure it was given — check before giving it.');
    });

    test('warm, specific copy with the pet name; household line only when shared', () {
      final solo = plan(now: nyNow(2026, 10, 4, 7)).first;
      expect(solo.title, "Miso's Insulin · 8:00 AM");
      expect(solo.body, '2 units. Tap Given when it’s done.');
      final shared = plan(now: nyNow(2026, 10, 4, 7), shared: true).first;
      expect(
        shared.body,
        '2 units. Tap Given when it’s done — we’ll let the household know.',
      );
      expect(solo.actionable, isTrue);
    });

    test('course end, future start, removed pet and stopped medicine', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 7),
        meds: [
          _med('abx', parts: [DayPart.morning], endDay: '2026-10-05'),
          _med('later', parts: [DayPart.morning], startDay: '2026-10-09'),
          _med('ghost', petId: 'gone', parts: [DayPart.morning]),
        ],
      ).where((n) => n.kind == ReminderKind.dose);
      expect(
        [for (final n in result) '${n.doseId} ${n.day}'],
        [
          'abx.morning 2026-10-04',
          'abx.morning 2026-10-05',
          'later.morning 2026-10-09',
          'later.morning 2026-10-10',
        ],
      );
    });

    test('stays well under the iOS 64 pending limit with many medicines', () {
      // Distinct minutes, so grouping can't shrink the count: the budget bites.
      final meds = [
        for (var i = 0; i < 6; i++)
          _med(
            'm$i',
            parts: DayPart.values,
            times: {
              DayPart.morning: 7 * 60 + i,
              DayPart.afternoon: 12 * 60 + i,
              DayPart.evening: 19 * 60 + i,
            },
          ),
      ];
      final result = plan(now: nyNow(2026, 10, 4, 6), meds: meds);
      final doseLike = result.where((n) => n.actionable).toList();
      expect(doseLike.length, ReminderPlanner.doseBudget);
      expect(result.length, lessThan(64));
      expect(doseLike.first.when, tz.TZDateTime(ny, 2026, 10, 4, 7));
      expect(doseLike.any((n) => n.isGroup), isFalse);
    });

    test('photo is attached only to the next day of reminders', () {
      const withPhoto = Pet(
        id: 'miso',
        name: 'Miso',
        species: Species.cat,
        ageYears: 1,
        breed: '',
        sex: '',
        conditions: [],
        weightKg: 4,
        onTimePercent: 100,
        dailyMeds: 1,
        photoPath: '/tmp/miso.jpg',
      );
      final result = plan(now: nyNow(2026, 10, 4, 7), pets: [withPhoto]);
      expect(result.first.photoPath, '/tmp/miso.jpg');
      expect(result.last.photoPath, isNull);
    });
  });

  group('time zones and DST', () {
    test('8:00 AM local on both sides of the November DST change', () {
      // US DST ends Sun Nov 1 2026 at 2:00 AM.
      final doses = plan(now: nyNow(2026, 10, 30, 12))
          .where((n) => n.kind == ReminderKind.dose && n.doseId.endsWith('morning'))
          .toList();
      final before = doses.firstWhere((n) => n.day == '2026-10-31');
      final after = doses.firstWhere((n) => n.day == '2026-11-02');
      expect(before.when.hour, 8);
      expect(after.when.hour, 8);
      // EDT (UTC-4) → EST (UTC-5): the UTC instant moves, the wall time doesn't.
      expect(before.when.toUtc().hour, 12);
      expect(after.when.toUtc().hour, 13);
    });

    test('spring forward keeps 8:00 AM', () {
      final doses = plan(now: nyNow(2026, 3, 7, 12))
          .where((n) => n.kind == ReminderKind.dose && n.doseId.endsWith('morning'));
      for (final n in doses) {
        expect(n.when.hour, 8, reason: n.day);
      }
      final mar9 = doses.firstWhere((n) => n.day == '2026-03-09');
      expect(mar9.when.toUtc().hour, 12);
    });

    test('travel: the same schedule lands at 8:00 in the new zone', () {
      final tokyo = tz.getLocation('Asia/Tokyo');
      final now = tz.TZDateTime(tokyo, 2026, 10, 4, 7);
      final first = plan(now: now, location: tokyo).first;
      expect(first.when.location.name, 'Asia/Tokyo');
      expect(first.when.hour, 8);
      expect(first.day, '2026-10-04');
    });
  });

  group('follow-up', () {
    test('one, 30 minutes after, only within the next 24 hours', () {
      final result = plan(now: nyNow(2026, 10, 4, 7));
      final follow = result.where((n) => n.kind == ReminderKind.followUp).toList();
      expect(
        [for (final n in follow) n.when],
        [
          tz.TZDateTime(ny, 2026, 10, 4, 8, 30),
          tz.TZDateTime(ny, 2026, 10, 4, 20, 30),
        ],
      );
      expect(follow.first.title, "Still due: Miso's Insulin");
      expect(follow.first.body, 'Was it given? Tap Given once it’s done.');
    });

    test('still sent when the reminder time passed but the follow-up has not', () {
      final result = plan(now: nyNow(2026, 10, 4, 8, 10));
      expect(result.first.kind, ReminderKind.followUp);
      expect(result.first.when, tz.TZDateTime(ny, 2026, 10, 4, 8, 30));
    });

    test('off in settings, or snoozed: none', () {
      expect(
        plan(
          now: nyNow(2026, 10, 4, 7),
          settings: const ReminderSettings(followUp: false, weeklySummary: false),
        ).where((n) => n.kind == ReminderKind.followUp),
        isEmpty,
      );
      final snoozed = plan(
        now: nyNow(2026, 10, 4, 8, 5),
        snoozed: {'insulin.morning|2026-10-04'},
      );
      expect(
        snoozed.where((n) => n.kind == ReminderKind.followUp && n.day == '2026-10-04' && n.doseId == 'insulin.morning'),
        isEmpty,
      );
    });
  });

  group('quiet hours', () {
    test('wraps past midnight', () {
      const s = ReminderSettings();
      expect(s.isQuiet(22 * 60), isTrue);
      expect(s.isQuiet(3 * 60), isTrue);
      expect(s.isQuiet(7 * 60), isFalse);
      expect(s.isQuiet(12 * 60), isFalse);
      expect(const ReminderSettings(quietHours: false).isQuiet(23 * 60), isFalse);
      const day = ReminderSettings(quietStartMinute: 9 * 60, quietEndMinute: 17 * 60);
      expect(day.isQuiet(10 * 60), isTrue);
      expect(day.isQuiet(18 * 60), isFalse);
    });

    test('engagement notifications move to the end of quiet hours', () {
      final at = tz.TZDateTime(ny, 2026, 10, 4, 23);
      expect(
        ReminderPlanner.outOfQuiet(at, const ReminderSettings()),
        tz.TZDateTime(ny, 2026, 10, 5, 7),
      );
      final early = tz.TZDateTime(ny, 2026, 10, 4, 5);
      expect(
        ReminderPlanner.outOfQuiet(early, const ReminderSettings()),
        tz.TZDateTime(ny, 2026, 10, 4, 7),
      );
    });

    test('dose reminders are never moved by quiet hours', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 7),
        settings: const ReminderSettings(
          weeklySummary: false,
          quietStartMinute: 19 * 60,
          quietEndMinute: 21 * 60,
        ),
      );
      expect(result.where((n) => n.kind == ReminderKind.dose).elementAt(1).when.hour, 20);
    });
  });

  group('weekly summary', () {
    // Sun Oct 4 2026 is a Sunday; the next summary is that evening.
    List<DoseRecord> weekLogs({int skip = 0}) => [
      for (var d = 28; d <= 34; d++)
        for (final part in [DayPart.morning, DayPart.evening])
          _log(
            'insulin',
            part,
            '2026-${d <= 30 ? '09' : '10'}-${(d <= 30 ? d : d - 30).toString().padLeft(2, '0')}',
          ),
    ].skip(skip).toList();

    test('Sunday evening with the counts known now', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 17),
        logs: weekLogs(skip: 1),
        settings: const ReminderSettings(),
        isPro: true,
      );
      final weekly = result.singleWhere((n) => n.kind == ReminderKind.weekly);
      expect(weekly.when, tz.TZDateTime(ny, 2026, 10, 4, 18));
      expect(weekly.title, "Miso's week");
      // Sun evening dose (8 PM) isn't due by 6 PM: 13 expected, 12 given.
      expect(weekly.body, '12 of 13 doses given this week.');
    });

    test('every dose given reads as warm, not as a score', () {
      final weekly = plan(
        now: nyNow(2026, 10, 4, 17),
        logs: weekLogs(),
        settings: const ReminderSettings(),
        isPro: true,
      ).singleWhere((n) => n.kind == ReminderKind.weekly);
      expect(weekly.body, startsWith('Every dose given this week — 13 of 13.'));
    });

    test(
      'scheduled days ahead says "so far"; nothing logged sends nothing',
      () {
        final early = plan(
          now: nyNow(2026, 9, 30, 21),
          logs: weekLogs(),
          settings: const ReminderSettings(),
          isPro: true,
        ).singleWhere((n) => n.kind == ReminderKind.weekly);
        expect(early.body, contains('so far'));
        final none = plan(
          now: nyNow(2026, 10, 4, 17),
          settings: const ReminderSettings(),
          isPro: true,
        ).where((n) => n.kind == ReminderKind.weekly);
        expect(
          none,
          isEmpty,
          reason: 'no guilt summary when nothing was logged',
        );
      },
    );

    test('Pro only: Free gets dose reminders, never the weekly recap', () {
      final free = plan(
        now: nyNow(2026, 10, 4, 17),
        logs: weekLogs(),
        settings: const ReminderSettings(),
      );
      expect(free.where((n) => n.kind == ReminderKind.weekly), isEmpty);
      expect(free.where((n) => n.kind == ReminderKind.dose), isNotEmpty);
    });

    test('opt-out and multi-pet copy', () {
      expect(
        plan(
          now: nyNow(2026, 10, 4, 17),
          logs: weekLogs(),
        ).where((n) => n.kind == ReminderKind.weekly),
        isEmpty,
      );
      final (title, body) = ReminderCopy.weekly([
        ('Miso', 13, 14),
        ('Bean', 7, 7),
      ], partial: false);
      expect(title, 'This week’s care');
      expect(body, 'Miso 13 of 14 · Bean 7 of 7 doses given.');
      final many = ReminderCopy.weekly([
        ('A', 1, 2),
        ('B', 2, 2),
        ('C', 3, 3),
        ('D', 4, 4),
      ], partial: false);
      expect(many.$2, 'Your pets got 10 of 11 doses this week.');
    });

    test('a summary time inside quiet hours moves out of them', () {
      final weekly = plan(
        now: nyNow(2026, 10, 4, 12),
        logs: weekLogs(),
        pets: const [_miso, _bean],
        settings: const ReminderSettings(
          quietStartMinute: 17 * 60,
          quietEndMinute: 19 * 60,
        ),
        isPro: true,
      ).singleWhere((n) => n.kind == ReminderKind.weekly);
      expect(weekly.when, tz.TZDateTime(ny, 2026, 10, 4, 19));
    });
  });

  group('refill heads-up', () {
    final low = _med(
      'insulin',
      parts: [DayPart.morning],
      supplyTotal: 30,
      dosesLeft: 2,
    );

    test('Pro only, next 9 AM, once per low episode', () {
      expect(
        plan(now: nyNow(2026, 10, 4, 10), meds: [low])
            .where((n) => n.kind == ReminderKind.refill),
        isEmpty,
        reason: 'Free: low-supply alerts stay a Pro feature',
      );
      final refill = plan(now: nyNow(2026, 10, 4, 10), meds: [low], isPro: true)
          .singleWhere((n) => n.kind == ReminderKind.refill);
      expect(refill.when, tz.TZDateTime(ny, 2026, 10, 5, 9));
      expect(refill.title, "Refill soon: Miso's Insulin");
      expect(refill.body, startsWith('About 2 doses left'));
      final shown = plan(
        now: nyNow(2026, 10, 5, 10),
        meds: [low],
        isPro: true,
        refill: {'insulin': refill.when.millisecondsSinceEpoch},
      ).where((n) => n.kind == ReminderKind.refill);
      expect(shown, isEmpty, reason: 'already shown — no daily nag');
    });
  });

  group('copy', () {
    test('already given, by someone else or by you', () {
      expect(
        ReminderCopy.alreadyBody(
          who: 'Sam',
          isYou: false,
          petName: 'Miso',
          medName: 'Insulin',
          timeLabel: '8:02 AM',
          outcome: LogOutcome.given,
        ),
        "Sam gave Miso's Insulin at 8:02 AM — no need to give it again.",
      );
      expect(
        ReminderCopy.alreadyBody(
          who: 'Sam',
          isYou: true,
          petName: 'Miso',
          medName: 'Insulin',
          timeLabel: '8:02 AM',
          outcome: LogOutcome.skipped,
        ),
        "You marked Miso's Insulin as skipped at 8:02 AM.",
      );
    });
  });
}
