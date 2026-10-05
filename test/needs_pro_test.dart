import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_reminder_platform.dart';
import 'support/sample_household.dart';
import 'test_log_helpers.dart';

/// A medicine the server marked "needs Pro" (saved over Free’s limits by an
/// old or modified app, or Pro that ended before an offline add synced).
Medication _locked(String today) => Medication(
  id: 'locked',
  petId: 'juniper',
  name: 'Gabapentin',
  amount: '50 mg',
  parts: const [DayPart.evening],
  supplyTotal: 0,
  dosesLeft: 0,
  startDay: today,
  needsPro: true,
);

/// The sample household plus one marked medicine.
CareRepository _care(DateTime now) {
  final care = sampleCare(clock: () => now);
  final today = dayKey(now);
  care.debugLoadHousehold(
    members: care.members,
    pets: care.pets,
    medications: [...care.medications, _locked(today)],
    logs: care.logs,
  );
  return care;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'reminders_on': true});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  group('wire and saved format', () {
    test('read from the server; absent means not marked', () {
      final base = {
        'id': 'm',
        'petId': 'p',
        'name': 'M',
        'parts': ['morning'],
        'startDay': '2026-10-04',
      };
      expect(medicationFromJson(base).needsPro, isFalse);
      expect(medicationFromJson({...base, 'needsPro': true}).needsPro, isTrue);
      expect(
        medicationFromJson({...base, 'needsPro': 'yes'}).needsPro,
        isFalse,
      );
      // Round-trips through the saved JSON; unmarked stays absent.
      final marked = medicationFromJson({...base, 'needsPro': true});
      expect(medicationFromJson(marked.toJson()).needsPro, isTrue);
      expect(
        medicationFromJson(base).toJson().containsKey('needsPro'),
        isFalse,
      );
      // copyWith keeps it unless told otherwise.
      expect(marked.copyWith(dosesLeft: 3).needsPro, isTrue);
      expect(marked.copyWith(needsPro: false).needsPro, isFalse);
    });

    group('SQLite', () {
      late Directory dir;
      late String path;

      setUp(() {
        dir = Directory.systemTemp.createTempSync('pawsitive_needs_pro_');
        path = '${dir.path}/${LocalDatabase.fileName}';
      });

      tearDown(() async {
        await LocalDatabase.shared.close();
        dir.deleteSync(recursive: true);
      });

      test('a v2 file gains needs_pro; old rows read as not marked', () async {
        final v2 = await databaseFactoryFfiNoIsolate.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
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
                  archived INTEGER NOT NULL, archived_at TEXT, times TEXT)''');
            },
          ),
        );
        await v2.insert('medications', {
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
        await v2.close();

        LocalDatabase.shared = LocalDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: () async => path,
        );
        final db = (await LocalDatabase.shared.open())!;
        expectLogged('store.migrated', fields: {'from': 2, 'to': 3});
        final row = (await db.query('medications')).single;
        final med = LocalRows.toMedication(row);
        expect(med.needsPro, isFalse);
        await db.update(
          'medications',
          LocalRows.medication(med.copyWith(needsPro: true), 0),
        );
        final again = LocalRows.toMedication(
          (await db.query('medications')).single,
        );
        expect(again.needsPro, isTrue);
        // Nothing else changed on the way.
        expect(again.parts, [DayPart.morning, DayPart.evening]);
      });
    });
  });

  group('repository', () {
    test(
      'Free: locked, still on Today, still logs, counts toward the cap',
      () async {
        final care = _care(DateTime(2026, 10, 4, 21));
        final med = care.medicationById('locked')!;
        expect(care.isMedicationLocked(med), isTrue);
        expect(care.lockedMedications.map((m) => m.id), ['locked']);
        final dose = care.doses.firstWhere((d) => d.medicationId == 'locked');
        expect(
          await care.logDose(
            doseId: dose.id,
            memberId: 'you',
            amount: '50 mg',
            timeLabel: '9:00 PM',
          ),
          isTrue,
          reason: 'safety is free: a marked medicine always logs',
        );
        expect(care.canAddMedication('juniper'), isFalse);
      },
    );

    test('Pro: nothing is locked', () {
      final care = _care(DateTime(2026, 10, 4, 21))..debugStorePro = true;
      expect(care.isMedicationLocked(care.medicationById('locked')!), isFalse);
      expect(care.lockedMedications, isEmpty);
    });
  });

  group('reminders', () {
    late FakeReminderPlatform fake;

    setUp(() {
      fake = FakeReminderPlatform();
      DoseReminders.platform = fake;
    });
    tearDown(DoseReminders.resetForTest);

    bool remindsLocked() => fake.scheduled.values.any(
      (n) =>
          n.kind == ReminderKind.dose &&
          (n.doseId.startsWith('locked.') ||
              n.group.any((g) => g.doseId.startsWith('locked.'))),
    );

    test('paused on Free, back with Pro; other medicines unaffected', () async {
      final care = _care(DateTime.utc(2026, 10, 4, 6));
      await DoseReminders.reschedule(care);
      expect(remindsLocked(), isFalse);
      expect(fake.ofKind(ReminderKind.dose), isNotEmpty);

      care.debugStorePro = true;
      await DoseReminders.reschedule(care, reason: 'pro');
      expect(remindsLocked(), isTrue);
    });
  });

  group('Today', () {
    Future<void> pump(WidgetTester tester, CareRepository care) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = OnboardingViewModel()..isComplete = true;
      final router = createRouter(model);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: care),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        model.dispose();
        care.dispose();
      });
    }

    const banner = 'Gabapentin: reminders paused on Free. Doses still log.';
    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;

    testWidgets(
      'Free shows the paused-reminders banner; it opens the paywall',
      (tester) async {
        await pump(tester, _care(DateTime(2026, 10, 4, 14)));
        await tester.scrollUntilVisible(
          find.text(banner),
          150,
          scrollable: scroll,
        );
        expect(find.text(banner), findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(find.text(banner)),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(banner));
        await tester.pumpAndSettle();
        expect(find.text('Morning and evening, both covered'), findsOneWidget);
      },
    );

    testWidgets('Pro shows no banner', (tester) async {
      await pump(
        tester,
        _care(DateTime(2026, 10, 4, 14))..debugStorePro = true,
      );
      // Scroll the whole page so a banner further down can’t hide.
      await tester.dragUntilVisible(
        find.text('Juniper').first,
        scroll,
        const Offset(0, -300),
      );
      await tester.fling(scroll, const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();
      expect(find.text(banner), findsNothing);
    });
  });
}
