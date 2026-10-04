import 'dart:convert';
import 'dart:math';

import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:timezone/timezone.dart' as tz;

/// What a local notification is for. The index is part of its id, so never
/// reorder — only append.
enum ReminderKind {
  dose,
  followUp,
  snooze,
  weekly,
  refill,
  alreadyLogged,
  household,
}

/// Stable notification ids: `(kind + 1) << 27 | fnv1a(key) & 0x7FFFFFF`.
///
/// Derived from data (dose id + local day), not a counter, so any isolate —
/// a background push, a notification action, the next launch — can cancel
/// exactly one dose's reminder without knowing what was scheduled.
abstract final class ReminderIds {
  static const _shift = 27;
  static const _mask = (1 << _shift) - 1;

  /// The single id the app used before multi-dose reminders. Cancelled on
  /// upgrade so an old pending reminder can't fire for a given dose.
  static const legacy = 1;

  static int of(ReminderKind kind, String key) =>
      ((kind.index + 1) << _shift) | (_fnv1a(key) & _mask);

  static int forDose(ReminderKind kind, String doseId, String day) =>
      of(kind, '$doseId|$day');

  /// The kind an id belongs to, or null for ids this app doesn't own.
  static ReminderKind? kindOf(int id) {
    final index = (id >> _shift) - 1;
    if (index < 0 || index >= ReminderKind.values.length) return null;
    return ReminderKind.values[index];
  }

  // Dart's String.hashCode is not guaranteed stable across runs/isolates.
  static int _fnv1a(String key) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(key)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// One notification the app wants pending. [payload] carries everything a
/// tap, an action, or a background snooze needs (no repository lookups).
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.kind,
    required this.when,
    required this.title,
    required this.body,
    this.doseId = '',
    this.day = '',
    this.photoPath,
  });

  final int id;
  final ReminderKind kind;
  final tz.TZDateTime when;
  final String title;
  final String body;
  final String doseId;
  final String day;

  /// Local pet photo for the iOS attachment / Android large icon.
  final String? photoPath;

  /// True for dose-type notifications that get Given / Snooze actions.
  bool get actionable =>
      kind == ReminderKind.dose ||
      kind == ReminderKind.followUp ||
      kind == ReminderKind.snooze;

  /// Same payload = same notification; the scheduler skips re-adding it.
  String get payload => ReminderPayload(
    kind: kind,
    doseId: doseId,
    day: day,
    at: when.millisecondsSinceEpoch,
    title: title,
    body: body,
  ).encode();
}

/// The JSON a notification carries back to the app.
class ReminderPayload {
  const ReminderPayload({
    required this.kind,
    this.doseId = '',
    this.day = '',
    this.at = 0,
    this.title = '',
    this.body = '',
  });

  final ReminderKind kind;
  final String doseId;
  final String day;
  final int at;
  final String title;
  final String body;

  String get doseKey => '$doseId|$day';

  String encode() => jsonEncode({
    'k': kind.name,
    if (doseId.isNotEmpty) 'd': doseId,
    if (day.isNotEmpty) 'day': day,
    'at': at,
    't': title,
    'b': body,
  });

  /// Null for junk or payloads from other notifications (old versions).
  static ReminderPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final kind = ReminderKind.values.where((k) => k.name == json['k']);
      if (kind.isEmpty) return null;
      return ReminderPayload(
        kind: kind.first,
        doseId: json['d'] is String ? json['d'] as String : '',
        day: json['day'] is String ? json['day'] as String : '',
        at: json['at'] is int ? json['at'] as int : 0,
        title: json['t'] is String ? json['t'] as String : '',
        body: json['b'] is String ? json['b'] as String : '',
      );
    } on FormatException {
      return null;
    }
  }
}

/// Notification copy. Warm and specific, never guilt or fake urgency; pet
/// names only ever go to the notification itself, never to logs.
abstract final class ReminderCopy {
  static String _possessive(String name) => "$name's";

  static String doseTitle(String petName, String medName, DayPart part) =>
      '${_possessive(petName)} $medName · ${part.timeLabel}';

  static String doseBody({
    required String amount,
    required bool shared,
    String? unsureBy,
  }) {
    if (unsureBy != null) {
      return '$unsureBy wasn’t sure it was given — check before giving it.';
    }
    final lead = amount.isEmpty ? '' : '$amount. ';
    return shared
        ? '${lead}Tap Given when it’s done — we’ll let the household know.'
        : '${lead}Tap Given when it’s done.';
  }

  static String followUpTitle(String petName, String medName) =>
      'Still due: ${_possessive(petName)} $medName';

  static const followUpBody = 'Was it given? Tap Given once it’s done.';

  static String snoozeBody(String amount) => amount.isEmpty
      ? 'Snoozed reminder. Tap Given when it’s done.'
      : 'Snoozed reminder · $amount. Tap Given when it’s done.';

  static const alreadyTitle = 'Already given';

  /// "Sam gave Miso's Insulin at 8:02 AM — no need to give it again."
  static String alreadyBody({
    required String who,
    required bool isYou,
    required String petName,
    required String medName,
    required String timeLabel,
    required LogOutcome outcome,
  }) {
    final what = '${_possessive(petName)} $medName';
    final at = timeLabel.isEmpty ? '' : ' at $timeLabel';
    if (outcome == LogOutcome.skipped) {
      return '${isYou ? 'You' : who} marked $what as skipped$at.';
    }
    return '${isYou ? 'You' : who} gave $what$at — no need to give it again.';
  }

  static String refillTitle(String petName, String medName) =>
      'Refill soon: ${_possessive(petName)} $medName';

  static String refillBody(int dosesLeft, String lastsUntil) {
    final left = dosesLeft == 1 ? '1 dose left' : 'About $dosesLeft doses left';
    return lastsUntil.isEmpty
        ? '$left — a good moment to reorder.'
        : '$left — enough until around $lastsUntil.';
  }

  /// [counts] is (pet name, given, expected) per pet with doses this week.
  static (String, String) weekly(
    List<(String, int, int)> counts, {
    required bool partial,
  }) {
    final soFar = partial ? ' so far' : '';
    if (counts.length == 1) {
      final (name, given, expected) = counts.single;
      final title = '${_possessive(name)} week';
      if (given >= expected) {
        return (
          title,
          'Every dose given$soFar this week — $given of $expected. $name’s in good hands.',
        );
      }
      return (title, '$given of $expected doses given$soFar this week.');
    }
    if (counts.length <= 3) {
      final parts = [
        for (final (name, given, expected) in counts)
          '$name $given of $expected',
      ];
      return ('This week’s care', '${parts.join(' · ')} doses given$soFar.');
    }
    final given = counts.fold(0, (sum, c) => sum + c.$2);
    final expected = counts.fold(0, (sum, c) => sum + c.$3);
    return (
      'This week’s care',
      'Your pets got $given of $expected doses$soFar this week.',
    );
  }
}

/// Everything the planner needs; plain data so it is easy to test.
class ReminderPlanInput {
  const ReminderPlanInput({
    required this.now,
    required this.location,
    required this.pets,
    required this.medications,
    required this.logs,
    required this.memberNames,
    required this.settings,
    this.shared = false,
    this.isPro = false,
    this.snoozedKeys = const {},
    this.refillNotifiedAt = const {},
  });

  /// The device clock (wall time is read in [location]).
  final DateTime now;
  final tz.Location location;
  final List<Pet> pets;
  final List<Medication> medications;
  final List<DoseRecord> logs;

  /// Member id → display name ("You" for this phone's member).
  final Map<String, String> memberNames;
  final ReminderSettings settings;

  /// Someone else can see the log (household of 2+).
  final bool shared;
  final bool isPro;

  /// `doseId|day` keys the person snoozed: no follow-up on top of a snooze.
  final Set<String> snoozedKeys;

  /// Medication id → epoch ms its refill heads-up was scheduled for.
  final Map<String, int> refillNotifiedAt;
}

/// Pure: which notifications should be pending right now.
abstract final class ReminderPlanner {
  /// Days of dose reminders scheduled ahead (nearest first, within budget).
  static const horizonDays = 7;

  /// Follow-ups only for the next day; further out a reminder matters more.
  static const followUpWindow = Duration(hours: 24);

  /// Dose reminders + follow-ups. iOS keeps at most 64 pending per app;
  /// this leaves room for snoozes and the engagement notifications.
  static const doseBudget = 52;

  /// Photo attachments only within this window (iOS copies the file).
  static const photoWindow = Duration(hours: 24);

  static String dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static List<PlannedNotification> plan(ReminderPlanInput input) {
    final now = tz.TZDateTime.from(input.now, input.location);
    return [..._doses(input, now), ..._engagement(input, now)];
  }

  static List<PlannedNotification> _doses(
    ReminderPlanInput input,
    tz.TZDateTime now,
  ) {
    final petsById = {for (final p in input.pets) p.id: p};
    // Latest log per dose-day (logs are newest first).
    final logs = <String, DoseRecord>{};
    for (final log in input.logs) {
      logs.putIfAbsent('${log.medicationId}.${log.part.name}|${log.day}', () => log);
    }
    final candidates = <PlannedNotification>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      // Calendar arithmetic on y/m/d, so DST never shifts the day.
      final date = DateTime(now.year, now.month, now.day + offset);
      final day = dayKey(date);
      for (final part in DayPart.values) {
        for (final med in input.medications) {
          if (med.isArchived || !med.parts.contains(part)) continue;
          if (!med.isActiveOn(day)) continue;
          final pet = petsById[med.petId];
          if (pet == null) continue;
          final doseId = '${med.id}.${part.name}';
          final log = logs['$doseId|$day'];
          if (log != null && log.outcome != LogOutcome.uncertain) continue;
          final at = tz.TZDateTime(
            input.location,
            date.year,
            date.month,
            date.day,
            part.hour,
          );
          final photo = pet.photoPath;
          String? photoFor(tz.TZDateTime when) =>
              when.difference(now) <= photoWindow ? photo : null;
          final unsureBy = log == null
              ? null
              : input.memberNames[log.memberId] ?? 'Someone';
          final title = ReminderCopy.doseTitle(pet.name, med.name, part);
          if (at.isAfter(now)) {
            candidates.add(
              PlannedNotification(
                id: ReminderIds.forDose(ReminderKind.dose, doseId, day),
                kind: ReminderKind.dose,
                when: at,
                title: title,
                body: ReminderCopy.doseBody(
                  amount: med.amount,
                  shared: input.shared,
                  unsureBy: unsureBy,
                ),
                doseId: doseId,
                day: day,
                photoPath: photoFor(at),
              ),
            );
          }
          final follow = at.add(ReminderSettings.followUpDelay);
          if (input.settings.followUp &&
              follow.isAfter(now) &&
              follow.difference(now) <= followUpWindow &&
              !input.snoozedKeys.contains('$doseId|$day')) {
            candidates.add(
              PlannedNotification(
                id: ReminderIds.forDose(ReminderKind.followUp, doseId, day),
                kind: ReminderKind.followUp,
                when: follow,
                title: ReminderCopy.followUpTitle(pet.name, med.name),
                body: ReminderCopy.followUpBody,
                doseId: doseId,
                day: day,
                photoPath: photoFor(follow),
              ),
            );
          }
        }
      }
    }
    candidates.sort((a, b) => a.when.compareTo(b.when));
    return candidates.take(doseBudget).toList();
  }

  static List<PlannedNotification> _engagement(
    ReminderPlanInput input,
    tz.TZDateTime now,
  ) {
    final result = <PlannedNotification>[];
    final weekly = _weekly(input, now);
    if (weekly != null) result.add(weekly);
    result.addAll(_refills(input, now));
    return result;
  }

  /// Moves an engagement notification out of quiet hours (to their end).
  static tz.TZDateTime outOfQuiet(tz.TZDateTime when, ReminderSettings s) {
    if (!s.isQuiet(when.hour * 60 + when.minute)) return when;
    var end = tz.TZDateTime(
      when.location,
      when.year,
      when.month,
      when.day,
      s.quietEndMinute ~/ 60,
      s.quietEndMinute % 60,
    );
    if (!end.isAfter(when)) {
      end = tz.TZDateTime(
        when.location,
        when.year,
        when.month,
        when.day + 1,
        s.quietEndMinute ~/ 60,
        s.quietEndMinute % 60,
      );
    }
    return end;
  }

  /// Next Sunday at [ReminderSettings.weeklyMinute], with the counts known
  /// now. Skipped when there's nothing honest to say (no doses, none logged).
  static PlannedNotification? _weekly(
    ReminderPlanInput input,
    tz.TZDateTime now,
  ) {
    final s = input.settings;
    if (!s.weeklySummary) return null;
    var date = DateTime(now.year, now.month, now.day);
    late tz.TZDateTime at;
    for (var i = 0; i < 8; i++) {
      final d = DateTime(date.year, date.month, date.day + i);
      if (d.weekday != DateTime.sunday) continue;
      at = tz.TZDateTime(
        input.location,
        d.year,
        d.month,
        d.day,
        s.weeklyMinute ~/ 60,
        s.weeklyMinute % 60,
      );
      if (at.isAfter(now)) {
        date = d;
        break;
      }
    }
    if (!at.isAfter(now)) return null;
    final given = <String, int>{};
    final expected = <String, int>{};
    final logged = <String>{
      for (final log in input.logs)
        if (log.outcome == LogOutcome.given)
          '${log.medicationId}.${log.part.name}|${log.day}',
    };
    for (var back = 6; back >= 0; back--) {
      final d = DateTime(date.year, date.month, date.day - back);
      final day = dayKey(d);
      for (final med in input.medications) {
        if (med.isArchived || !med.isActiveOn(day)) continue;
        for (final part in med.parts) {
          final due = tz.TZDateTime(
            input.location,
            d.year,
            d.month,
            d.day,
            part.hour,
          );
          // Only doses whose time has come by now (and by the summary).
          if (due.isAfter(now) || due.isAfter(at)) continue;
          expected[med.petId] = (expected[med.petId] ?? 0) + 1;
          if (logged.contains('${med.id}.${part.name}|$day')) {
            given[med.petId] = (given[med.petId] ?? 0) + 1;
          }
        }
      }
    }
    final counts = [
      for (final pet in input.pets)
        if ((expected[pet.id] ?? 0) > 0)
          (pet.name, given[pet.id] ?? 0, expected[pet.id]!),
    ];
    final totalGiven = counts.fold(0, (sum, c) => sum + c.$2);
    final totalExpected = counts.fold(0, (sum, c) => sum + c.$3);
    if (totalExpected < 3 || totalGiven == 0) return null;
    // Counts are as of now; say "so far" when the app may not see the rest.
    final partial = at.difference(now) > const Duration(hours: 24);
    final (title, body) = ReminderCopy.weekly(counts, partial: partial);
    final when = outOfQuiet(at, s);
    return PlannedNotification(
      id: ReminderIds.of(ReminderKind.weekly, dayKey(date)),
      kind: ReminderKind.weekly,
      when: when,
      title: title,
      body: body,
      day: dayKey(date),
    );
  }

  /// Pro only: one heads-up per low-supply episode, at the next 9:00 AM
  /// outside quiet hours. [ReminderPlanInput.refillNotifiedAt] stops repeats.
  static List<PlannedNotification> _refills(
    ReminderPlanInput input,
    tz.TZDateTime now,
  ) {
    if (!input.isPro || !input.settings.refill) return const [];
    final petsById = {for (final p in input.pets) p.id: p};
    final result = <PlannedNotification>[];
    for (final med in input.medications) {
      if (med.isArchived || !med.isLow) continue;
      final pet = petsById[med.petId];
      if (pet == null) continue;
      final sent = input.refillNotifiedAt[med.id];
      tz.TZDateTime when;
      if (sent != null) {
        if (sent <= now.millisecondsSinceEpoch) continue; // already shown
        when = tz.TZDateTime.fromMillisecondsSinceEpoch(input.location, sent);
      } else {
        when = tz.TZDateTime(input.location, now.year, now.month, now.day, 9);
        if (!when.isAfter(now.add(const Duration(minutes: 5)))) {
          when = tz.TZDateTime(
            input.location,
            now.year,
            now.month,
            now.day + 1,
            9,
          );
        }
        when = outOfQuiet(when, input.settings);
      }
      result.add(
        PlannedNotification(
          id: ReminderIds.of(ReminderKind.refill, med.id),
          kind: ReminderKind.refill,
          when: when,
          title: ReminderCopy.refillTitle(pet.name, med.name),
          body: ReminderCopy.refillBody(
            max(med.dosesLeft, 0),
            med.lastsUntil(input.now),
          ),
          doseId: med.id,
        ),
      );
    }
    return result;
  }
}
