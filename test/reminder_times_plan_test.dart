import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/data/household_api.dart';
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

const _biscuit = Pet(
  id: 'biscuit',
  name: 'Biscuit',
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
  List<DayPart> parts = const [DayPart.morning, DayPart.evening],
  Map<DayPart, int> times = const {},
  String startDay = '2026-01-01',
  String endDay = '',
}) => Medication(
  id: id,
  petId: petId,
  name: name,
  amount: '2 units',
  parts: parts,
  supplyTotal: 0,
  dosesLeft: 0,
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
  timeLabel: '7:02 AM',
);

const _insulinTimes = {DayPart.morning: 7 * 60, DayPart.evening: 19 * 60};

void main() {
  tzdata.initializeTimeZones();
  final ny = tz.getLocation('America/New_York');

  tearDown(ClockFormat.resetForTest);

  List<PlannedNotification> plan({
    required DateTime now,
    required List<Medication> meds,
    List<Pet> pets = const [_miso, _biscuit],
    List<DoseRecord> logs = const [],
    ReminderSettings settings = const ReminderSettings(weeklySummary: false),
    Set<String> resolved = const {},
    bool isPro = false,
  }) => ReminderPlanner.plan(
    ReminderPlanInput(
      now: now,
      location: ny,
      pets: pets,
      medications: meds,
      logs: logs,
      memberNames: const {'you': 'You', 'dan': 'Dan'},
      settings: settings,
      resolvedKeys: resolved,
      isPro: isPro,
    ),
  );

  DateTime nyNow(int y, int m, int d, int h, [int min = 0]) =>
      tz.TZDateTime(ny, y, m, d, h, min);

  List<PlannedNotification> doses(List<PlannedNotification> all) =>
      all.where((n) => n.kind == ReminderKind.dose).toList();

  group('custom time per dose', () {
    test('insulin at 7:00 and 19:00 is reminded then, not an hour late', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 6),
        meds: [_med('insulin', times: _insulinTimes)],
      );
      final d = doses(result);
      expect(d[0].when, tz.TZDateTime(ny, 2026, 10, 4, 7));
      expect(d[1].when, tz.TZDateTime(ny, 2026, 10, 4, 19));
      expect(d[0].title, "Miso’s Insulin · 7:00 AM");
      expect(d[1].title, "Miso’s Insulin · 7:00 PM");
      final follow = result.firstWhere((n) => n.kind == ReminderKind.followUp);
      expect(follow.when, tz.TZDateTime(ny, 2026, 10, 4, 7, 30));
    });

    test('old saved data without times uses the part defaults', () {
      final old = medicationFromJson({
        'id': 'insulin',
        'petId': 'miso',
        'name': 'Insulin',
        'parts': ['morning', 'evening'],
        'startDay': '2026-01-01',
      });
      expect(old.times, isEmpty);
      expect(old.minuteFor(DayPart.morning), 8 * 60);
      final d = doses(plan(now: nyNow(2026, 10, 4, 6), meds: [old]));
      expect(d.first.when.hour, 8);
      expect(d.first.title, "Miso’s Insulin · 8:00 AM");
    });

    test(
      'junk or unknown times from a garbled store fall back, never crash',
      () {
        final parsed = medicationFromJson({
          'id': 'x',
          'petId': 'miso',
          'name': 'X',
          'parts': ['morning'],
          'startDay': '2026-01-01',
          'times': {
            'morning': '25:00',
            'evening': '19:00', // not a selected part
            'noon': '12:00',
          },
        });
        expect(parsed.times, isEmpty);
        expect(DoseTimes.parse('nope'), isEmpty);
        expect(DoseTimes.parseClock('7:00'), isNull);
        expect(DoseTimes.parseClock('23:59'), 23 * 60 + 59);
        expect(DoseTimes.parseClock('00:00'), 0);
      },
    );

    test(
      '23:59 today and 00:00 (start of the next day) land on the right days',
      () {
        final result = doses(
          plan(
            now: nyNow(2026, 10, 4, 6),
            meds: [
              _med(
                'late',
                parts: [DayPart.evening],
                times: {DayPart.evening: 23 * 60 + 59},
              ),
              _med(
                'midnight',
                name: 'Gaba',
                parts: [DayPart.morning],
                times: {DayPart.morning: 0},
              ),
            ],
          ),
        );
        final late = result.firstWhere((n) => n.doseId == 'late.evening');
        expect(late.day, '2026-10-04');
        expect(late.when, tz.TZDateTime(ny, 2026, 10, 4, 23, 59));
        // 00:00 today is already past at 6 AM: the first one is tomorrow’s.
        final midnight = result.firstWhere(
          (n) => n.doseId == 'midnight.morning',
        );
        expect(midnight.day, '2026-10-05');
        expect(midnight.when, tz.TZDateTime(ny, 2026, 10, 5));
        expect(midnight.title, "Miso’s Gaba · 12:00 AM");
      },
    );

    test('24-hour phones read 07:00 / 19:00 in the copy', () {
      ClockFormat.use24h.value = true;
      final d = doses(
        plan(
          now: nyNow(2026, 10, 4, 6),
          meds: [_med('insulin', times: _insulinTimes)],
        ),
      );
      expect(d[0].title, "Miso’s Insulin · 07:00");
      expect(d[1].title, "Miso’s Insulin · 19:00");
    });

    test('DST gap: 02:30 on spring-forward day fires once at the next valid instant', () {
      // US DST starts Sun Mar 8 2026: 2:00 AM jumps to 3:00 AM.
      final result = doses(
        plan(
          now: nyNow(2026, 3, 7, 12),
          meds: [
            _med(
              'night',
              parts: [DayPart.morning],
              times: {DayPart.morning: 2 * 60 + 30},
            ),
          ],
        ),
      );
      final gapDay = result.where((n) => n.day == '2026-03-08').toList();
      expect(
        gapDay,
        hasLength(1),
        reason: 'exactly one reminder, not zero or two',
      );
      final when = gapDay.single.when;
      // 02:30 doesn’t exist; 03:30 EDT (07:30 UTC) is the next valid instant.
      expect(when.toUtc(), DateTime.utc(2026, 3, 8, 7, 30));
      expect(when.hour, 3);
      final next = result.firstWhere((n) => n.day == '2026-03-09');
      expect(next.when.hour, 2);
      expect(next.when.minute, 30);
    });

    test('DST fall-back: an ambiguous 01:30 fires once', () {
      // US DST ends Sun Nov 1 2026: 1:00–2:00 AM happens twice.
      final result = doses(
        plan(
          now: nyNow(2026, 10, 31, 12),
          meds: [
            _med(
              'night',
              parts: [DayPart.morning],
              times: {DayPart.morning: 90},
            ),
          ],
        ),
      );
      final ambiguous = result.where((n) => n.day == '2026-11-01').toList();
      expect(ambiguous, hasLength(1));
      expect(ambiguous.single.when.hour, 1);
      expect(ambiguous.single.when.minute, 30);
    });

    test(
      'time changed for today after today’s dose was logged: no reminder today',
      () {
        final result = doses(
          plan(
            now: nyNow(2026, 10, 4, 6),
            meds: [
              _med('insulin', times: {DayPart.morning: 6 * 60 + 30}),
            ],
            logs: [_log('insulin', DayPart.morning, '2026-10-04')],
          ),
        );
        expect(
          result.where(
            (n) => n.doseId == 'insulin.morning' && n.day == '2026-10-04',
          ),
          isEmpty,
        );
        expect(
          result.firstWhere((n) => n.doseId == 'insulin.morning').day,
          '2026-10-05',
        );
      },
    );

    test('time moved earlier than now: no past reminder today, tomorrow at the new time', () {
      final result = doses(
        plan(
          now: nyNow(2026, 10, 4, 9),
          meds: [
            _med(
              'insulin',
              parts: [DayPart.morning],
              times: {DayPart.morning: 7 * 60},
            ),
          ],
        ),
      );
      expect(
        result.every((n) => n.when.isAfter(nyNow(2026, 10, 4, 9))),
        isTrue,
      );
      expect(result.first.day, '2026-10-05');
      expect(result.first.when, tz.TZDateTime(ny, 2026, 10, 5, 7));
    });

    test(
      'the dose is due from the earlier of its part opening and its time',
      () {
        final m = _med(
          'x',
          parts: DayPart.values,
          times: {
            DayPart.morning: 7 * 60,
            DayPart.afternoon: 11 * 60,
            DayPart.evening: 15 * 60 + 30,
          },
        );
        expect(m.dueFromMinute(DayPart.morning), 0);
        expect(m.dueFromMinute(DayPart.afternoon), 11 * 60);
        expect(m.dueFromMinute(DayPart.evening), 15 * 60 + 30);
        // A late evening time never makes it due later than usual.
        final late = _med(
          'y',
          parts: [DayPart.evening],
          times: {DayPart.evening: 22 * 60},
        );
        expect(late.dueFromMinute(DayPart.evening), 17 * 60);
        expect(
          m.timesLabel,
          'Morning 7:00 AM, afternoon 11:00 AM & evening 3:30 PM',
        );
      },
    );

    test('weekly summary counts a custom-time dose once it is due', () {
      // Sunday Oct 4 at 17:00; evening dose at 16:00 counts, default 20:00 wouldn’t.
      final logs = [
        for (var d = 28; d <= 34; d++)
          _log(
            'insulin',
            DayPart.evening,
            '2026-${d <= 30 ? '09' : '10'}-${(d <= 30 ? d : d - 30).toString().padLeft(2, '0')}',
          ),
      ];
      final weekly = plan(
        now: nyNow(2026, 10, 4, 17),
        meds: [
          _med(
            'insulin',
            parts: [DayPart.evening],
            times: {DayPart.evening: 16 * 60},
          ),
        ],
        logs: logs,
        settings: const ReminderSettings(),
        isPro: true,
      ).singleWhere((n) => n.kind == ReminderKind.weekly);
      expect(weekly.body, startsWith('Every dose given this week — 7 of 7.'));
    });
  });

  group('same-time doses → one notification', () {
    final sameTime = [
      _med('insulin', parts: [DayPart.morning]),
      _med(
        'apoquel',
        petId: 'biscuit',
        name: 'Apoquel',
        parts: [DayPart.morning],
      ),
      _med(
        'fishoil',
        petId: 'biscuit',
        name: 'Fish oil',
        parts: [DayPart.morning],
      ),
    ];

    test(
      'title counts the doses, body lists them per pet, ids stay unique',
      () {
        final result = plan(now: nyNow(2026, 10, 4, 7), meds: sameTime);
        final first = doses(result).first;
        expect(first.isGroup, isTrue);
        expect(first.title, '3 doses due · 8:00 AM');
        expect(first.body, 'Miso: Insulin · Biscuit: Apoquel, Fish oil');
        expect(first.groupKey, 'g|2026-10-04|480');
        expect(first.id, ReminderIds.of(ReminderKind.dose, 'g|2026-10-04|480'));
        expect(first.doseId, isEmpty);
        expect(doses(result), hasLength(7), reason: 'one per day, not three');
        expect({for (final n in result) n.id}, hasLength(result.length));
        // Follow-ups group the same way.
        final follow = result.firstWhere(
          (n) => n.kind == ReminderKind.followUp,
        );
        expect(follow.title, 'Still due: 3 doses from 8:00 AM');
        expect(follow.body, 'Miso: Insulin · Biscuit: Apoquel, Fish oil');
        expect(
          follow.id,
          ReminderIds.of(ReminderKind.followUp, 'g|2026-10-04|480'),
        );
      },
    );

    test('payload carries the group and round-trips', () {
      final first = doses(plan(now: nyNow(2026, 10, 4, 7), meds: sameTime))
          .first;
      final back = ReminderPayload.decode(first.payload)!;
      expect(back.isGroup, isTrue);
      expect(back.group.map((g) => g.doseId), [
        'insulin.morning',
        'apoquel.morning',
        'fishoil.morning',
      ]);
      expect(back.doseKeys, contains('apoquel.morning|2026-10-04'));
      expect(back.timeLabel, '8:00 AM');
      expect(back.groupKey, first.groupKey);
    });

    test(
      'one logged → the group shrinks (same id); two logged → that dose alone',
      () {
        final full = doses(plan(now: nyNow(2026, 10, 4, 7), meds: sameTime))
            .first;
        final two = doses(
          plan(
            now: nyNow(2026, 10, 4, 7),
            meds: sameTime,
            logs: [_log('apoquel', DayPart.morning, '2026-10-04')],
          ),
        ).first;
        expect(two.id, full.id);
        expect(two.title, '2 doses due · 8:00 AM');
        expect(two.body, 'Miso: Insulin · Biscuit: Fish oil');
        expect(
          two.payload,
          isNot(full.payload),
          reason: 'pending copy is replaced',
        );
        final one = doses(
          plan(
            now: nyNow(2026, 10, 4, 7),
            meds: sameTime,
            logs: [
              _log('apoquel', DayPart.morning, '2026-10-04'),
              _log('fishoil', DayPart.morning, '2026-10-04'),
            ],
          ),
        ).first;
        expect(one.isGroup, isFalse);
        expect(
          one.id,
          ReminderIds.forDose(
            ReminderKind.dose,
            'insulin.morning',
            '2026-10-04',
          ),
        );
        expect(one.title, "Miso’s Insulin · 8:00 AM");
      },
    );

    test(
      'a push-resolved dose (not yet synced) leaves the group before grouping',
      () {
        final result = doses(
          plan(
            now: nyNow(2026, 10, 4, 7),
            meds: sameTime,
            resolved: {'insulin.morning|2026-10-04'},
          ),
        );
        expect(result.first.title, '2 doses due · 8:00 AM');
      },
    );

    test('a "not sure" dose keeps its own check-first notification', () {
      final result = doses(
        plan(
          now: nyNow(2026, 10, 4, 7),
          meds: sameTime,
          logs: [
            _log(
              'insulin',
              DayPart.morning,
              '2026-10-04',
              outcome: LogOutcome.uncertain,
              memberId: 'dan',
            ),
          ],
        ),
      ).where((n) => n.day == '2026-10-04').toList();
      expect(result, hasLength(2));
      final unsure = result.firstWhere((n) => !n.isGroup);
      expect(
        unsure.body,
        'Dan wasn’t sure it was given — check before giving it.',
      );
      expect(
        result.firstWhere((n) => n.isGroup).title,
        '2 doses due · 8:00 AM',
      );
    });

    test('different minutes are never grouped', () {
      final result = doses(
        plan(
          now: nyNow(2026, 10, 4, 7),
          meds: [
            _med('insulin', parts: [DayPart.morning]),
            _med(
              'apoquel',
              petId: 'biscuit',
              name: 'Apoquel',
              parts: [DayPart.morning],
              times: {DayPart.morning: 8 * 60 + 1},
            ),
          ],
        ),
      );
      expect(result.where((n) => n.isGroup), isEmpty);
    });

    test(
      'rebuild from a payload drops resolved doses (background, no household)',
      () {
        final first = doses(plan(now: nyNow(2026, 10, 4, 7), meds: sameTime))
            .first;
        final payload = ReminderPayload.decode(first.payload)!;
        final rest = ReminderGroups.without(payload, {
          'fishoil.morning|2026-10-04',
        }, ny)!;
        expect(rest.id, first.id);
        expect(rest.when, first.when);
        expect(rest.title, '2 doses due · 8:00 AM');
        final single = ReminderGroups.without(payload, {
          'fishoil.morning|2026-10-04',
          'apoquel.morning|2026-10-04',
        }, ny)!;
        expect(
          single.id,
          ReminderIds.forDose(
            ReminderKind.dose,
            'insulin.morning',
            '2026-10-04',
          ),
        );
        expect(single.body, '2 units. Tap Given when it’s done.');
        expect(
          ReminderGroups.without(payload, payload.doseKeys.toSet(), ny),
          isNull,
        );
      },
    );
  });

  group('keep-reminders-going safety net', () {
    test('one quiet note at the last scheduled dose when doses continue', () {
      final result = plan(now: nyNow(2026, 10, 4, 6), meds: [_med('insulin')]);
      final upkeep = result.singleWhere((n) => n.kind == ReminderKind.upkeep);
      final lastDose = doses(result).last;
      expect(upkeep.when, lastDose.when);
      expect(upkeep.day, '2026-10-10');
      expect(upkeep.id, ReminderPlanner.upkeepId);
      expect(upkeep.body, "Open Pawsitive to keep Miso’s reminders going.");
      expect(upkeep.actionable, isFalse);
    });

    test('replaced, not added, when a later reschedule extends the window', () {
      final first = plan(
        now: nyNow(2026, 10, 4, 6),
        meds: [_med('insulin')],
      ).singleWhere((n) => n.kind == ReminderKind.upkeep);
      final later = plan(
        now: nyNow(2026, 10, 6, 6),
        meds: [_med('insulin')],
      ).singleWhere((n) => n.kind == ReminderKind.upkeep);
      expect(later.id, first.id, reason: 'same id → the OS replaces it');
      expect(later.when.isAfter(first.when), isTrue);
      expect(later.day, '2026-10-12');
      expect(later.payload, isNot(first.payload));
    });

    test('names every pet whose doses continue', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 6),
        meds: [
          _med('insulin'),
          _med('apoquel', petId: 'biscuit', name: 'Apoquel'),
        ],
      );
      expect(
        result.singleWhere((n) => n.kind == ReminderKind.upkeep).body,
        "Open Pawsitive to keep Miso and Biscuit’s reminders going.",
      );
    });

    test('a course ending inside the window needs no nudge', () {
      final result = plan(
        now: nyNow(2026, 10, 4, 6),
        meds: [_med('abx', endDay: '2026-10-06')],
      );
      expect(result.where((n) => n.kind == ReminderKind.upkeep), isEmpty);
    });

    test('budget-truncated plan still gets the nudge', () {
      final meds = [
        for (var i = 0; i < 6; i++)
          _med(
            'm$i',
            parts: DayPart.values,
            endDay: '2026-10-06',
            times: {
              DayPart.morning: 7 * 60 + i,
              DayPart.afternoon: 12 * 60 + i,
              DayPart.evening: 19 * 60 + i,
            },
          ),
      ];
      // Ends Oct 6 but 52 slots don’t even reach it: still nudged.
      final result = plan(now: nyNow(2026, 10, 4, 6), meds: meds);
      expect(result.where((n) => n.kind == ReminderKind.upkeep), hasLength(1));
    });
  });

  group('fresh plan after a long gap (reboot, app unopened for weeks)', () {
    test('starts from now: nothing in the past, a full window ahead', () {
      final now = nyNow(2026, 11, 20, 13);
      final result = plan(
        now: now,
        meds: [_med('insulin', times: _insulinTimes)],
      );
      final d = doses(result);
      expect(result.every((n) => n.when.isAfter(now)), isTrue);
      expect(d.first.when, tz.TZDateTime(ny, 2026, 11, 20, 19));
      expect(d.last.day, '2026-11-26');
      expect(d, hasLength(13));
      expect({for (final n in result) n.id}, hasLength(result.length));
    });
  });
}
