import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:provider/provider.dart';

/// A one-pet household with [medication] and [logs], on a clock the test
/// moves with [at].
({CareRepository care, void Function(DateTime) at}) _household({
  List<DayPart> parts = const [DayPart.morning],
  Map<DayPart, int> times = const {},
  List<DoseRecord> logs = const [],
  required DateTime now,
}) {
  var time = now;
  final care = CareRepository(clock: () => time);
  care.debugLoadHousehold(
    members: const [
      Member(
        id: 'sara',
        name: 'Sara',
        initials: 'S',
        role: MemberRole.caregiver,
        avatarTone: AvatarTone.soft,
      ),
    ],
    pets: const [
      Pet(
        id: 'biscuit',
        name: 'Biscuit',
        species: Species.dog,
        ageYears: 4,
        breed: '',
        sex: '',
        conditions: [],
        weightKg: 12,
        onTimePercent: 0,
        dailyMeds: 0,
      ),
    ],
    medications: [
      Medication(
        id: 'carprofen',
        petId: 'biscuit',
        name: 'Carprofen',
        amount: '1 tablet',
        parts: parts,
        times: times,
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: '2026-10-01',
      ),
      Medication(
        id: 'other',
        petId: 'biscuit',
        name: 'Other',
        amount: '',
        parts: const [DayPart.morning],
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: '2026-10-01',
      ),
    ],
    logs: logs,
  );
  return (care: care, at: (t) => time = t);
}

DoseRecord _log(
  String day,
  String timeLabel, {
  String id = 'log-1',
  String medicationId = 'carprofen',
  DayPart part = DayPart.morning,
  LogOutcome outcome = LogOutcome.given,
  String memberId = 'sara',
}) => DoseRecord(
  id: id,
  medicationId: medicationId,
  part: part,
  day: day,
  memberId: memberId,
  outcome: outcome,
  amount: '',
  timeLabel: timeLabel,
);

void main() {
  group('givenTimeOf reads every clock the app and the sitter page write', () {
    final day = DateTime(2026, 10, 13);
    for (final (label, hour, minute) in [
      ('8:02 AM', 8, 2),
      ('11:51 PM', 23, 51),
      ('12:05 AM', 0, 5),
      ('12:30 PM', 12, 30),
      ('23:51', 23, 51),
      ('0:05', 0, 5),
      ('08:02', 8, 2),
      ('11:51 p.m.', 23, 51),
      ('12:05am', 0, 5),
      ('  7:00 pm ', 19, 0),
    ]) {
      test(label, () {
        expect(
          givenTimeOf('2026-10-13', label),
          DateTime(day.year, day.month, day.day, hour, minute),
        );
      });
    }

    for (final label in [
      '',
      'soon',
      '25:00',
      '13:00 PM',
      '0:30 AM',
      '8:60 AM',
      '8 AM',
      '8:02 XM',
    ]) {
      test('unreadable "$label" is null, never a guess', () {
        expect(givenTimeOf('2026-10-13', label), isNull);
      });
    }

    test('an unreadable day is null', () {
      expect(givenTimeOf('yesterday', '8:02 AM'), isNull);
    });
  });

  group('recentlyGiven', () {
    setUp(AppLog.enableTestCapture);
    tearDown(AppLog.disableTestCapture);

    test('catches 11:51 PM then 12:05 AM across midnight', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 5),
        logs: [_log('2026-10-13', '11:51 PM')],
      );
      final recent = h.care.recentlyGiven('carprofen');
      expect(recent?.log.id, 'log-1');
      expect(recent?.ago, const Duration(minutes: 14));
    });

    test('once a day: warns until 12 h, not at 12 h', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 7, 50),
        logs: [_log('2026-10-13', '7:51 PM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNotNull); // 11 h 59
      h.at(DateTime(2026, 10, 14, 7, 51));
      expect(h.care.recentlyGiven('carprofen'), isNull); // 12 h exactly
    });

    test('yesterday morning is not recent this morning', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 8, 30),
        logs: [_log('2026-10-13', '8:00 AM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('twice a day: the window is 6 h', () {
      final h = _household(
        parts: const [DayPart.morning, DayPart.evening],
        now: DateTime(2026, 10, 14, 13, 59),
        logs: [_log('2026-10-14', '8:00 AM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNotNull); // 5 h 59
      h.at(DateTime(2026, 10, 14, 14, 0));
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('three times a day at default times: the window is 2.5 h', () {
      // 8:00, 13:00, 20:00: the shortest gap is 5 h.
      final h = _household(
        parts: DayPart.values,
        now: DateTime(2026, 10, 14, 10, 29),
        logs: [_log('2026-10-14', '8:00 AM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNotNull);
      h.at(DateTime(2026, 10, 14, 10, 30));
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('custom times close together shrink the window', () {
      // Vet: 8:00 and 10:00. Shortest gap 2 h, so the window is 1 h.
      final h = _household(
        parts: const [DayPart.morning, DayPart.afternoon],
        times: const {DayPart.morning: 8 * 60, DayPart.afternoon: 10 * 60},
        now: DateTime(2026, 10, 14, 10, 0),
        logs: [_log('2026-10-14', '8:00 AM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull); // on schedule
      h.at(DateTime(2026, 10, 14, 8, 50));
      expect(h.care.recentlyGiven('carprofen'), isNotNull); // 50 min
    });

    test('custom times wrap past midnight', () {
      // 22:00 and 02:00: the short gap crosses midnight (4 h → 2 h window).
      final h = _household(
        parts: const [DayPart.morning, DayPart.evening],
        times: const {DayPart.morning: 2 * 60, DayPart.evening: 22 * 60},
        now: DateTime(2026, 10, 14, 0, 30),
        logs: [_log('2026-10-13', '10:00 PM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull); // 2 h 30 later
      h.at(DateTime(2026, 10, 13, 23, 30));
      expect(h.care.recentlyGiven('carprofen'), isNotNull); // 1 h 30
    });

    test('only given doses count: skipped and not sure are ignored', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 5),
        logs: [
          _log('2026-10-13', '11:51 PM', outcome: LogOutcome.skipped),
          _log(
            '2026-10-13',
            '11:55 PM',
            id: 'log-2',
            outcome: LogOutcome.uncertain,
          ),
        ],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('another medicine never counts', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 5),
        logs: [_log('2026-10-13', '11:51 PM', medicationId: 'other')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('the latest of several recent doses wins', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 30),
        logs: [
          _log('2026-10-13', '11:00 PM'),
          _log('2026-10-14', '12:10 AM', id: 'log-2'),
        ],
      );
      expect(h.care.recentlyGiven('carprofen')?.log.id, 'log-2');
    });

    test('a label later than now (clock moved back) is not recent', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 8, 0),
        logs: [_log('2026-10-14', '9:00 AM')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull);
    });

    test('an unreadable label is skipped and logged, not guessed', () {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 5),
        logs: [_log('2026-10-13', 'late')],
      );
      expect(h.care.recentlyGiven('carprofen'), isNull);
      expect(AppLog.logged('dose.recent_unreadable'), isTrue);
    });

    test('a stopped or unknown medicine is null', () {
      final h = _household(now: DateTime(2026, 10, 14, 0, 5));
      expect(h.care.recentlyGiven('gone'), isNull);
    });
  });

  group('log dose sheet', () {
    setUp(AppLog.enableTestCapture);
    tearDown(AppLog.disableTestCapture);

    Future<void> openSheet(WidgetTester tester, CareRepository care) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: care,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showLogDoseSheet(
                      context,
                      care.doses.firstWhere(
                        (d) => d.medicationId == 'carprofen',
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('warns about the 11:51 PM dose and still lets you log', (
      tester,
    ) async {
      final h = _household(
        now: DateTime(2026, 10, 14, 0, 5),
        logs: [_log('2026-10-13', '11:51 PM')],
      );
      final dose = h.care.doses.firstWhere(
        (d) => d.medicationId == 'carprofen',
      );
      expect(dose.status, DoseStatus.due, reason: 'test needs a due dose');
      await openSheet(tester, h.care);
      expect(
        find.textContaining(
          'Sara gave Carprofen 14 min ago (yesterday at 11:51 PM)',
        ),
        findsOneWidget,
      );
      expect(AppLog.logged('dose.recent_warning'), isTrue);

      // A warning, not a block: the owner may know it's right.
      await tester.tap(find.text('Confirm given'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(AppLog.logged('dose.log.completed'), isTrue);
    });

    testWidgets('no warning when the last dose was long ago', (tester) async {
      final h = _household(
        now: DateTime(2026, 10, 14, 8, 30),
        logs: [_log('2026-10-13', '8:00 AM')],
      );
      await openSheet(tester, h.care);
      expect(find.textContaining('can be unsafe'), findsNothing);
      expect(AppLog.logged('dose.recent_warning'), isFalse);
    });
  });
}
