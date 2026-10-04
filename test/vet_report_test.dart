import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/vet_report_pdf.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mutable clock so a test can log on several days.
class _Clock {
  DateTime time = DateTime(2026, 10, 1, 21);
  DateTime call() => time;
}

Future<(CareRepository, String, _Clock)> _care({
  String petName = 'Milo',
}) async {
  final clock = _Clock();
  final care = CareRepository(store: HouseholdStore(), clock: clock.call);
  final petId = (await care.addPet(name: petName, species: Species.cat))!;
  return (care, petId, clock);
}

String _doseId(CareRepository care, String name, DayPart part) =>
    care.doses.firstWhere((d) => d.name == name && d.part == part).id;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  test('given, skipped, not sure and missed are counted separately', () async {
    final (care, petId, clock) = await _care();
    await care.addMedication(
      petId: petId,
      name: 'Insulin',
      amount: '2 u',
      parts: const [DayPart.morning, DayPart.evening],
    );
    // Day 1 (Oct 1, 9 PM): give morning, "not sure" evening.
    await care.logDose(
      doseId: _doseId(care, 'Insulin', DayPart.morning),
      memberId: 'you',
      amount: '2 u',
      timeLabel: '8:00 AM',
    );
    await care.markDoseUncertain(_doseId(care, 'Insulin', DayPart.evening));
    // Day 2: skip morning, nothing in the evening (missed).
    clock.time = DateTime(2026, 10, 2, 21);
    await care.skipDose(_doseId(care, 'Insulin', DayPart.morning));

    final report = care.reportFor(petId, 7);
    final line = report.lines.single;
    expect(line.expected, 4);
    expect(line.given, 1);
    expect(line.skipped, 1);
    expect(line.uncertain, 1);
    expect(line.missed, 1);
    expect(report.skipped, 1, reason: '"not sure" is not "skipped on purpose"');
    expect(report.uncertain, 1);
    expect(report.missedDoses.single.part, DayPart.evening);
    expect(report.missedDoses.single.day, DateTime(2026, 10, 2));
  });

  test('a removed medicine still appears with its in-range history', () async {
    final (care, petId, clock) = await _care();
    await care.addMedication(
      petId: petId,
      name: 'Antibiotic',
      amount: '50 mg',
      parts: const [DayPart.morning],
    );
    await care.logDose(
      doseId: _doseId(care, 'Antibiotic', DayPart.morning),
      memberId: 'you',
      amount: '50 mg',
      timeLabel: '8:00 AM',
    );
    final medId = care.medications.single.id;
    clock.time = DateTime(2026, 10, 3, 9);
    await care.removeMedication(medId);
    expect(care.medications, isEmpty);

    final report = care.reportFor(petId, 7);
    final line = report.lines.single;
    expect(line.medication.name, 'Antibiotic');
    expect(line.removed, isTrue);
    expect(line.given, 1);

    // Survives a restart.
    await care.flushPersist();
    final reloaded = CareRepository(store: HouseholdStore(), clock: clock.call);
    await reloaded.restore();
    expect(
      reloaded.reportFor(petId, 7).lines.single.medication.name,
      'Antibiotic',
    );
  });

  test(
    'recent doses are limited to the range, newest first, with outcome',
    () async {
      final (care, petId, clock) = await _care();
      await care.addMedication(
        petId: petId,
        name: 'Insulin',
        amount: '2 u',
        parts: const [DayPart.morning],
      );
      await care.logDose(
        doseId: _doseId(care, 'Insulin', DayPart.morning),
        memberId: 'you',
        amount: '2 u',
        timeLabel: '8:00 AM',
      );
      clock.time = DateTime(2026, 10, 20, 21);
      await care.skipDose(_doseId(care, 'Insulin', DayPart.morning));

      final week = care.reportFor(petId, 7);
      expect(
        week.recent,
        hasLength(1),
        reason: 'Oct 1 is outside the last 7 days',
      );
      expect(week.recent.single.outcome, LogOutcome.skipped);
      expect(week.recent.single.day, '2026-10-20');

      final month = care.reportFor(petId, 30);
      expect(month.recent.map((e) => e.day), ['2026-10-20', '2026-10-01']);
    },
  );

  test('PDF builds with a non-Latin pet name', () async {
    final (care, petId, _) = await _care(petName: 'میسو');
    await care.addMedication(
      petId: petId,
      name: 'Insulin',
      amount: '2 u',
      parts: const [DayPart.morning, DayPart.evening],
    );
    final pet = care.petById(petId);
    final pdf = await buildVetReportPdf(
      pet: pet,
      report: care.reportFor(petId, 30),
      showCaregivers: true,
      generatedAt: care.now,
      fonts: await VetReportFonts.load(),
    );
    expect(pdf.bytes, isNotEmpty);
    expect(String.fromCharCodes(pdf.bytes.take(5)), '%PDF-');
    expect(pdf.pages, greaterThanOrEqualTo(1));
    expect(
      vetReportFileName(pet, DateTime(2026, 10, 4)),
      'میسو-care-report-2026-10-04.pdf',
    );
  });
}
