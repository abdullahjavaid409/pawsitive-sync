import 'package:flutter_test/flutter_test.dart';

import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/today/today_v14.dart';

import 'support/sample_household.dart';

void main() {
  test('next dose after today is tomorrow’s earliest', () {
    final care = sampleCare();
    final next = care.nextAfterToday();
    expect(next, isNotNull);
    expect(next!.at, DateTime(2026, 10, 3, 8));
    expect(next.medication.parts, isNotEmpty);
  });

  test('narrowed to one pet', () {
    final care = sampleCare();
    final next = care.nextAfterToday(petId: 'juniper');
    expect(next!.medication.name, 'Joint supplement');
    expect(next.at.day, 3);
  });

  test('a pet with nothing scheduled has no next dose', () {
    final care = sampleCare();
    expect(care.nextAfterToday(petId: 'nobody'), isNull);
  });

  _dueWordTests();
}

void _dueWordTests() {
  test('a due dose reads "Due now", then "Late" after the follow-up delay', () {
    final care = sampleCare();
    final due = care.doses.firstWhere((d) => d.status == DoseStatus.due);
    final at = DateTime(
      2026,
      10,
      2,
      0,
      0,
    ).add(Duration(minutes: doseMinute(due)));
    expect(dueWord(due, at), 'Due now');
    expect(dueWord(due, at.add(const Duration(minutes: 29))), 'Due now');
    expect(dueWord(due, at.add(const Duration(minutes: 30))), 'Late');
    final later = care.doses.firstWhere((d) => d.status == DoseStatus.upcoming);
    expect(dueWord(later, at.add(const Duration(hours: 12))), 'Later today');
  });
}
