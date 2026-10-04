import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Sam gave Miso's Insulin — thanks, Sam" (in-app, from the synced log).
class ThankYou {
  const ThankYou({required this.logId, required this.text});
  final String logId;
  final String text;
}

/// A medicine course that ended in the last few days.
class CourseDone {
  const CourseDone({
    required this.medicationId,
    required this.title,
    required this.body,
  });
  final String medicationId;
  final String title;
  final String body;
}

/// Pure engagement rules over the local ledger. No network, no guilt:
/// nothing here is ever shown as lost, broken or overdue.
abstract final class Engagement {
  /// Care-day counts that get a one-time card.
  static const milestones = [7, 30, 100, 365];

  /// Course cards stay up this many days after the last day.
  static const courseCardDays = 3;

  /// Newest dose another member gave today, unless dismissed.
  static ThankYou? thanks({
    required List<DoseRecord> logs,
    required String today,
    required String myMemberId,
    required bool shared,
    required Set<String> dismissed,
    required String Function(String memberId) nameOf,
    required Medication? Function(String id) medication,
    required Pet? Function(String id) pet,
  }) {
    if (!shared) return null;
    for (final log in logs) {
      if (log.day != today) continue;
      if (log.outcome != LogOutcome.given) continue;
      if (log.memberId.isEmpty || log.memberId == myMemberId) continue;
      if (dismissed.contains(log.id)) return null; // newest already seen
      final med = medication(log.medicationId);
      final petName = med == null ? null : pet(med.petId)?.name;
      final who = nameOf(log.memberId);
      final what = med == null
          ? 'a dose'
          : petName == null
          ? med.name
          : "$petName's ${med.name}";
      return ThankYou(logId: log.id, text: '$who gave $what — thanks, $who');
    }
    return null;
  }

  /// Courses whose last day is today (once every dose of it is logged) or
  /// up to [courseCardDays] ago. Counts only what's in local history.
  static List<CourseDone> courses({
    required List<Medication> medications,
    required List<DoseRecord> logs,
    required DateTime now,
    required bool shared,
    required Set<String> dismissed,
    required String Function(String petId) petName,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = dayKey(today);
    final given = <String>{};
    final resolved = <String>{};
    for (final log in logs) {
      final key = '${log.medicationId}.${log.part.name}|${log.day}';
      if (log.outcome == LogOutcome.given) given.add(key);
      if (log.outcome != LogOutcome.uncertain) resolved.add(key);
    }
    final result = <CourseDone>[];
    for (final med in medications) {
      if (med.endDay.isEmpty || med.isArchived) continue;
      if (dismissed.contains(med.id)) continue;
      final end = DateTime.tryParse(med.endDay);
      final start = DateTime.tryParse(med.startDay);
      if (end == null || start == null || end.isBefore(start)) continue;
      final ago = today.difference(end).inDays;
      if (ago < 0 || ago >= courseCardDays) continue;
      if (med.endDay == todayKey &&
          !med.parts.every((p) => resolved.contains('${med.id}.${p.name}|$todayKey'))) {
        continue; // last day still has doses to give
      }
      var expected = 0;
      var got = 0;
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
        final day = dayKey(d);
        for (final part in med.parts) {
          expected++;
          if (given.contains('${med.id}.${part.name}|$day')) got++;
        }
      }
      if (expected == 0 || got == 0) continue;
      final pet = petName(med.petId);
      final full = got >= expected;
      result.add(
        CourseDone(
          medicationId: med.id,
          title: full ? '${med.name} course complete 🎉' : '${med.name} course finished',
          body: full
              ? '$pet got every dose — $got of $expected. Nice work${shared ? ', everyone' : ''}.'
              : '$pet got $got of $expected doses.',
        ),
      );
    }
    return result;
  }

  /// Days (YYYY-MM-DD) on which every scheduled dose was given, from
  /// [fromDay] through today. A day with nothing scheduled never counts.
  static Set<String> fullDays({
    required List<Medication> medications,
    required List<DoseRecord> logs,
    required DateTime now,
    required String fromDay,
  }) {
    final given = <String>{
      for (final log in logs)
        if (log.outcome == LogOutcome.given)
          '${log.medicationId}.${log.part.name}|${log.day}',
    };
    final start = DateTime.tryParse(fromDay);
    if (start == null) return const {};
    final result = <String>{};
    final today = DateTime(now.year, now.month, now.day);
    for (var d = start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
      final day = dayKey(d);
      var expected = 0;
      var complete = true;
      for (final med in medications) {
        if (med.isArchived || !med.isActiveOn(day)) continue;
        for (final part in med.parts) {
          expected++;
          if (!given.contains('${med.id}.${part.name}|$day')) complete = false;
        }
      }
      if (expected > 0 && complete) result.add(day);
    }
    return result;
  }

  /// Copy for a milestone card, or null.
  static String? milestoneText(int days, String petName) => switch (days) {
    7 => 'A full week of every dose given — $petName is lucky to have you.',
    30 => '30 days of every dose given. That’s real, steady care.',
    100 => '100 days of every dose given. Remarkable.',
    365 => 'A whole year of every dose given. Thank you.',
    _ => null,
  };
}

/// In-app engagement state: settings, dismissals and the cumulative care
/// count. Local only (SharedPreferences); never calls the server.
class EngagementState extends ChangeNotifier {
  static const _dismissedThanksKey = 'engagement_thanks_dismissed_v1';
  static const _dismissedCoursesKey = 'engagement_courses_dismissed_v1';
  static const _careDaysKey = 'engagement_care_days_v1';
  static const _milestoneKey = 'engagement_milestone_seen_v1';
  static const _nudgeKey = 'engagement_permission_nudge_until_v1';

  ReminderSettings settings = const ReminderSettings();
  final Set<String> _dismissedThanks = {};
  final Set<String> _dismissedCourses = {};

  /// Add-only: a day once counted stays counted (the count never drops).
  final Set<String> _careDays = {};
  int _milestoneSeen = 0;
  DateTime? _nudgeHiddenUntil;
  int? _lastInput;

  int get careDayCount => _careDays.length;

  /// The milestone reached but not yet dismissed, or null.
  int? get pendingMilestone {
    int? best;
    for (final m in Engagement.milestones) {
      if (careDayCount >= m && m > _milestoneSeen) best = m;
    }
    return best;
  }

  /// The permission note on Today is hidden until this time after "Not now".
  bool permissionNudgeHidden(DateTime now) =>
      _nudgeHiddenUntil != null && now.isBefore(_nudgeHiddenUntil!);

  Set<String> get dismissedThanks => _dismissedThanks;
  Set<String> get dismissedCourses => _dismissedCourses;

  Future<void> load() async {
    settings = await ReminderSettingsStore.read();
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedThanks.addAll(prefs.getStringList(_dismissedThanksKey) ?? const []);
      _dismissedCourses.addAll(prefs.getStringList(_dismissedCoursesKey) ?? const []);
      _careDays.addAll(prefs.getStringList(_careDaysKey) ?? const []);
      _milestoneSeen = prefs.getInt(_milestoneKey) ?? 0;
      final until = prefs.getInt(_nudgeKey);
      _nudgeHiddenUntil = until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until);
    } on Object catch (error, stack) {
      AppLog.error('store.engagement_failed', error, stack, {'op': 'read'});
    }
    notifyListeners();
  }

  /// Keeps the care count in step with [care]; cheap to call on every
  /// repository change (skips when nothing relevant changed).
  void update(CareRepository care) {
    final now = care.now;
    final input = Object.hash(
      dayKey(now),
      care.logs.length,
      care.logs.isEmpty ? '' : care.logs.first.id,
      Object.hashAll([for (final m in care.medications) Object.hash(m.id, m.startDay, m.endDay)]),
    );
    if (input == _lastInput) return;
    _lastInput = input;
    final days = Engagement.fullDays(
      medications: care.medications,
      logs: care.logs,
      now: now,
      fromDay: dayKey(now.subtract(const Duration(days: 100))),
    );
    final before = _careDays.length;
    _careDays.addAll(days);
    if (_careDays.length == before) return;
    AppLog.event('engagement.care_days', {'count': _careDays.length});
    final milestone = pendingMilestone;
    if (milestone != null) {
      AppLog.event('engagement.milestone_reached', {'days': milestone});
    }
    unawaited(_saveList(_careDaysKey, _careDays));
    notifyListeners();
  }

  /// Forgets everything (account deleted); preferences are wiped separately.
  void clear() {
    settings = const ReminderSettings();
    _dismissedThanks.clear();
    _dismissedCourses.clear();
    _careDays.clear();
    _milestoneSeen = 0;
    _nudgeHiddenUntil = null;
    _lastInput = null;
    notifyListeners();
  }

  Future<void> saveSettings(ReminderSettings next) async {
    final changed = <String, Object?>{
      for (final e in next.toJson().entries)
        if (settings.toJson()[e.key] != e.value) e.key: e.value,
    };
    settings = next;
    notifyListeners();
    AppLog.event('settings.engagement_changed', changed);
    await ReminderSettingsStore.write(next);
  }

  Future<void> dismissThanks(String logId) async {
    _dismissedThanks.add(logId);
    // Only the newest matter; keep the list short.
    while (_dismissedThanks.length > 50) {
      _dismissedThanks.remove(_dismissedThanks.first);
    }
    AppLog.event('engagement.thanks_dismissed', {'logId': logId});
    notifyListeners();
    await _saveList(_dismissedThanksKey, _dismissedThanks);
  }

  Future<void> dismissCourse(String medicationId) async {
    _dismissedCourses.add(medicationId);
    AppLog.event('engagement.course_dismissed', {'medicationId': medicationId});
    notifyListeners();
    await _saveList(_dismissedCoursesKey, _dismissedCourses);
  }

  Future<void> dismissMilestone(int days) async {
    _milestoneSeen = days;
    AppLog.event('engagement.milestone_dismissed', {'days': days});
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_milestoneKey, days);
    } on Object catch (error, stack) {
      AppLog.error('store.engagement_failed', error, stack, {'op': 'milestone'});
    }
  }

  /// "Not now" on the permission note: quiet for two weeks, not forever
  /// (Settings keeps showing the state).
  Future<void> hidePermissionNudge(DateTime now) async {
    _nudgeHiddenUntil = now.add(const Duration(days: 14));
    AppLog.event('reminders.permission_nudge_hidden');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_nudgeKey, _nudgeHiddenUntil!.millisecondsSinceEpoch);
    } on Object catch (error, stack) {
      AppLog.error('store.engagement_failed', error, stack, {'op': 'nudge'});
    }
  }

  Future<void> _saveList(String key, Set<String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, values.toList());
    } on Object catch (error, stack) {
      AppLog.error('store.engagement_failed', error, stack, {'op': key});
    }
  }
}
