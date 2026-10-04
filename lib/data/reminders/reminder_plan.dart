import 'dart:convert';
import 'dart:math';

import 'package:pawsitive_sync/core/format/clock_format.dart';
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

  /// The quiet "open the app to keep reminders going" safety net.
  upkeep,
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

/// One dose inside a grouped notification (same minute, several doses).
/// Carries the copy fields so a background isolate can rebuild the group
/// when one dose is resolved, without loading the household.
class GroupedDose {
  const GroupedDose({
    required this.doseId,
    required this.petName,
    required this.medName,
    this.amount = '',
  });

  final String doseId;
  final String petName;
  final String medName;
  final String amount;

  List<String> toJson() => [doseId, petName, medName, amount];

  static GroupedDose? fromJson(Object? json) {
    if (json is! List || json.length < 3) return null;
    final fields = [for (final v in json) v is String ? v : ''];
    if (fields[0].isEmpty) return null;
    return GroupedDose(
      doseId: fields[0],
      petName: fields[1],
      medName: fields[2],
      amount: fields.length > 3 ? fields[3] : '',
    );
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
    this.group = const [],
    this.groupKey = '',
    this.timeLabel = '',
    this.shared = false,
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

  /// Two or more doses due at the same minute, shown as one notification
  /// (empty for a single dose).
  final List<GroupedDose> group;

  /// `g|<day>|<minute of the dose time>` — the group's id key, shared by its
  /// reminder, follow-up and snooze.
  final String groupKey;

  /// The dose time as shown in the copy ("8:00 AM"), for rebuilding.
  final String timeLabel;

  /// Household copy ("we'll let the household know"), for rebuilding.
  final bool shared;

  bool get isGroup => group.isNotEmpty;

  /// True for dose-type notifications that get Given / Snooze actions
  /// (a group gets Open / Snooze instead).
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
    group: group,
    groupKey: groupKey,
    timeLabel: timeLabel,
    shared: shared,
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
    this.group = const [],
    this.groupKey = '',
    this.timeLabel = '',
    this.shared = false,
  });

  final ReminderKind kind;
  final String doseId;
  final String day;
  final int at;
  final String title;
  final String body;
  final List<GroupedDose> group;
  final String groupKey;
  final String timeLabel;
  final bool shared;

  bool get isGroup => group.isNotEmpty;

  String get doseKey => '$doseId|$day';

  /// Every `doseId|day` this notification is about (one, or the group's).
  List<String> get doseKeys => isGroup
      ? [for (final g in group) '${g.doseId}|$day']
      : [if (doseId.isNotEmpty) doseKey];

  String encode() => jsonEncode({
    'k': kind.name,
    if (doseId.isNotEmpty) 'd': doseId,
    if (day.isNotEmpty) 'day': day,
    'at': at,
    't': title,
    'b': body,
    if (group.isNotEmpty) 'g': [for (final g in group) g.toJson()],
    if (groupKey.isNotEmpty) 'gk': groupKey,
    if (timeLabel.isNotEmpty) 'tl': timeLabel,
    if (shared) 'sh': true,
  });

  /// Null for junk or payloads from other notifications (old versions).
  static ReminderPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final kind = ReminderKind.values.where((k) => k.name == json['k']);
      if (kind.isEmpty) return null;
      String str(String key) => json[key] is String ? json[key] as String : '';
      return ReminderPayload(
        kind: kind.first,
        doseId: str('d'),
        day: str('day'),
        at: json['at'] is int ? json['at'] as int : 0,
        title: str('t'),
        body: str('b'),
        group: [
          for (final g in json['g'] is List ? json['g'] as List : const [])
            ?GroupedDose.fromJson(g),
        ],
        groupKey: str('gk'),
        timeLabel: str('tl'),
        shared: json['sh'] == true,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Builds dose-type notifications for one or more doses at the same
/// minute. Shared by the planner, the push-cancel path and snooze, so a
/// group rebuilt in a background isolate reads exactly like a planned one.
abstract final class ReminderGroups {
  /// The group key for doses whose reminder time is [at] (local).
  static String keyFor(String day, tz.TZDateTime at) =>
      'g|$day|${at.hour * 60 + at.minute}';

  /// Two or more [doses] → one grouped notification (id from [groupKey]);
  /// one → that dose's own notification (its usual id, so per-dose
  /// cancellation keeps working); none → null.
  static PlannedNotification? build({
    required ReminderKind kind,
    required List<GroupedDose> doses,
    required tz.TZDateTime when,
    required String day,
    required String groupKey,
    required String timeLabel,
    required bool shared,
    String? photoPath,
  }) {
    if (doses.isEmpty) return null;
    if (doses.length == 1) {
      final d = doses.single;
      final (title, body) = switch (kind) {
        ReminderKind.followUp => (
          ReminderCopy.followUpTitle(d.petName, d.medName),
          ReminderCopy.followUpBody,
        ),
        ReminderKind.snooze => (
          ReminderCopy.doseTitle(d.petName, d.medName, timeLabel),
          ReminderCopy.snoozeBody(''),
        ),
        _ => (
          ReminderCopy.doseTitle(d.petName, d.medName, timeLabel),
          ReminderCopy.doseBody(amount: d.amount, shared: shared),
        ),
      };
      return PlannedNotification(
        id: ReminderIds.forDose(kind, d.doseId, day),
        kind: kind,
        when: when,
        title: title,
        body: body,
        doseId: d.doseId,
        day: day,
        photoPath: photoPath,
        timeLabel: timeLabel,
        shared: shared,
      );
    }
    final lines = ReminderCopy.groupLines(doses);
    final (title, body) = switch (kind) {
      ReminderKind.followUp => (
        ReminderCopy.groupFollowUpTitle(doses.length, timeLabel),
        lines,
      ),
      ReminderKind.snooze => (
        ReminderCopy.groupTitle(doses.length, timeLabel),
        'Snoozed · $lines',
      ),
      _ => (ReminderCopy.groupTitle(doses.length, timeLabel), lines),
    };
    return PlannedNotification(
      id: ReminderIds.of(kind, groupKey),
      kind: kind,
      when: when,
      title: title,
      body: body,
      day: day,
      group: doses,
      groupKey: groupKey,
      timeLabel: timeLabel,
      shared: shared,
    );
  }

  /// [payload]'s group without the doses in [resolvedKeys] (`doseId|day`),
  /// at the same time. Null when nothing is left.
  static PlannedNotification? without(
    ReminderPayload payload,
    Set<String> resolvedKeys,
    tz.Location location,
  ) {
    final left = [
      for (final g in payload.group)
        if (!resolvedKeys.contains('${g.doseId}|${payload.day}')) g,
    ];
    return build(
      kind: payload.kind,
      doses: left,
      when: tz.TZDateTime.fromMillisecondsSinceEpoch(location, payload.at),
      day: payload.day,
      groupKey: payload.groupKey,
      timeLabel: payload.timeLabel,
      shared: payload.shared,
    );
  }
}

/// Notification copy. Warm and specific, never guilt or fake urgency; pet
/// names only ever go to the notification itself, never to logs.
abstract final class ReminderCopy {
  static String _possessive(String name) => "$name's";

  /// "Miso's Insulin · 7:00 AM" — [timeLabel] is the dose's own time.
  static String doseTitle(String petName, String medName, String timeLabel) =>
      '${_possessive(petName)} $medName · $timeLabel';

  /// "3 doses due · 8:00 AM"
  static String groupTitle(int count, String timeLabel) =>
      '$count doses due · $timeLabel';

  /// "Still due: 3 doses from 8:00 AM"
  static String groupFollowUpTitle(int count, String timeLabel) =>
      'Still due: $count doses from $timeLabel';

  /// "Miso: Insulin · Biscuit: Apoquel, Fish oil" — pets in first-seen order.
  static String groupLines(List<GroupedDose> doses) {
    final byPet = <String, List<String>>{};
    for (final d in doses) {
      (byPet[d.petName] ??= []).add(d.medName);
    }
    return [
      for (final e in byPet.entries) '${e.key}: ${e.value.join(', ')}',
    ].join(' · ');
  }

  static const upkeepTitle = 'Keep reminders going';

  /// "Open Pawsitive to keep Miso's reminders going."
  static String upkeepBody(List<String> petNames) {
    final who = switch (petNames.length) {
      0 => 'your',
      1 => _possessive(petNames.single),
      2 => "${petNames[0]} and ${_possessive(petNames[1])}",
      _ => 'your pets’',
    };
    return 'Open Pawsitive to keep $who reminders going.';
  }

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
    this.resolvedKeys = const {},
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

  /// `doseId|day` keys another phone resolved (push) before this phone
  /// synced the log: treated like a log, before grouping.
  final Set<String> resolvedKeys;
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
    final doses = _doses(input, now);
    return [
      ...doses.notifications,
      ?_upkeep(input, doses.notifications, truncated: doses.truncated),
      ..._engagement(input, now),
    ];
  }

  /// The local instant of [minute] on [date]. A wall time that doesn't
  /// exist (DST spring-forward gap, e.g. 02:30) resolves to the next valid
  /// instant (03:30) by the tz rules; an ambiguous one (fall-back 01:30)
  /// resolves to a single instant. Either way: exactly one reminder.
  static tz.TZDateTime at(tz.Location location, DateTime date, int minute) =>
      tz.TZDateTime(
        location,
        date.year,
        date.month,
        date.day,
        minute ~/ 60,
        minute % 60,
      );

  static ({List<PlannedNotification> notifications, bool truncated}) _doses(
    ReminderPlanInput input,
    tz.TZDateTime now,
  ) {
    final petsById = {for (final p in input.pets) p.id: p};
    // Latest log per dose-day (logs are newest first).
    final logs = <String, DoseRecord>{};
    for (final log in input.logs) {
      logs.putIfAbsent('${log.medicationId}.${log.part.name}|${log.day}', () => log);
    }
    final due = <_Due>[];
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
          if (input.resolvedKeys.contains('$doseId|$day')) continue;
          final log = logs['$doseId|$day'];
          if (log != null && log.outcome != LogOutcome.uncertain) continue;
          final doseAt = at(input.location, date, med.minuteFor(part));
          final unsureBy = log == null
              ? null
              : input.memberNames[log.memberId] ?? 'Someone';
          final base = _Due(
            kind: ReminderKind.dose,
            when: doseAt,
            doseAt: doseAt,
            day: day,
            dose: GroupedDose(
              doseId: doseId,
              petName: pet.name,
              medName: med.name,
              amount: med.amount,
            ),
            timeLabel: med.timeLabelFor(part),
            unsureBy: unsureBy,
            photo: pet.photoPath,
          );
          if (doseAt.isAfter(now)) due.add(base);
          final follow = doseAt.add(ReminderSettings.followUpDelay);
          if (input.settings.followUp &&
              follow.isAfter(now) &&
              follow.difference(now) <= followUpWindow &&
              !input.snoozedKeys.contains('$doseId|$day')) {
            due.add(base.copy(kind: ReminderKind.followUp, when: follow));
          }
        }
      }
    }
    final notifications = _grouped(due, now, input.shared)
      ..sort((a, b) => a.when.compareTo(b.when));
    return (
      notifications: notifications.take(doseBudget).toList(),
      truncated: notifications.length > doseBudget,
    );
  }

  /// One notification per minute: doses of the same kind at the same
  /// instant collapse into a group. A "not sure" dose stays on its own —
  /// its check-first warning must not be lost in a list.
  static List<PlannedNotification> _grouped(
    List<_Due> due,
    tz.TZDateTime now,
    bool shared,
  ) {
    final buckets = <String, List<_Due>>{};
    final result = <PlannedNotification>[];
    for (final d in due) {
      if (d.unsureBy != null) {
        result.add(d.single(now, shared));
        continue;
      }
      (buckets['${d.kind.index}|${d.when.millisecondsSinceEpoch}'] ??= []).add(d);
    }
    for (final bucket in buckets.values) {
      if (bucket.length == 1) {
        result.add(bucket.single.single(now, shared));
        continue;
      }
      final first = bucket.first;
      result.add(
        ReminderGroups.build(
          kind: first.kind,
          doses: [for (final d in bucket) d.dose],
          when: first.when,
          day: first.day,
          groupKey: ReminderGroups.keyFor(first.day, first.doseAt),
          timeLabel: ClockFormat.label(first.doseAt.hour * 60 + first.doseAt.minute),
          shared: shared,
        )!,
      );
    }
    return result;
  }

  /// Id of the single "keep reminders going" notification; one at a time,
  /// replaced (same id, new time) whenever a reschedule extends the window.
  static final upkeepId = ReminderIds.of(ReminderKind.upkeep, 'window');

  /// Safety net for when the app isn't opened and background refresh never
  /// runs: at the last scheduled dose reminder, one quiet nudge to open the
  /// app — only when doses continue past what is scheduled.
  static PlannedNotification? _upkeep(
    ReminderPlanInput input,
    List<PlannedNotification> scheduled, {
    required bool truncated,
  }) {
    final last = scheduled.lastWhereOrNull((n) => n.kind == ReminderKind.dose);
    if (last == null) return null;
    final lastDate = DateTime(last.when.year, last.when.month, last.when.day);
    final nextDay = dayKey(
      DateTime(lastDate.year, lastDate.month, lastDate.day + 1),
    );
    final petsById = {for (final p in input.pets) p.id: p};
    final names = <String>[];
    for (final med in input.medications) {
      final pet = petsById[med.petId];
      if (med.isArchived || med.parts.isEmpty || pet == null) continue;
      final continues = med.isActiveOn(nextDay) || truncated;
      if (continues && !names.contains(pet.name)) names.add(pet.name);
    }
    if (names.isEmpty) return null;
    return PlannedNotification(
      id: upkeepId,
      kind: ReminderKind.upkeep,
      when: last.when,
      title: ReminderCopy.upkeepTitle,
      body: ReminderCopy.upkeepBody(names),
      day: last.day,
    );
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
          final due = ReminderPlanner.at(input.location, d, med.minuteFor(part));
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

/// One dose reminder or follow-up before grouping.
class _Due {
  const _Due({
    required this.kind,
    required this.when,
    required this.doseAt,
    required this.day,
    required this.dose,
    required this.timeLabel,
    this.unsureBy,
    this.photo,
  });

  final ReminderKind kind;
  final tz.TZDateTime when;

  /// The dose's own reminder time (a follow-up fires 30 min after it).
  final tz.TZDateTime doseAt;
  final String day;
  final GroupedDose dose;
  final String timeLabel;
  final String? unsureBy;
  final String? photo;

  _Due copy({required ReminderKind kind, required tz.TZDateTime when}) => _Due(
    kind: kind,
    when: when,
    doseAt: doseAt,
    day: day,
    dose: dose,
    timeLabel: timeLabel,
    unsureBy: unsureBy,
    photo: photo,
  );

  PlannedNotification single(tz.TZDateTime now, bool shared) {
    final photoPath =
        when.difference(now) <= ReminderPlanner.photoWindow ? photo : null;
    if (kind == ReminderKind.dose && unsureBy != null) {
      return PlannedNotification(
        id: ReminderIds.forDose(kind, dose.doseId, day),
        kind: kind,
        when: when,
        title: ReminderCopy.doseTitle(dose.petName, dose.medName, timeLabel),
        body: ReminderCopy.doseBody(
          amount: dose.amount,
          shared: shared,
          unsureBy: unsureBy,
        ),
        doseId: dose.doseId,
        day: day,
        photoPath: photoPath,
        timeLabel: timeLabel,
        shared: shared,
      );
    }
    return ReminderGroups.build(
      kind: kind,
      doses: [dose],
      when: when,
      day: day,
      groupKey: '',
      timeLabel: timeLabel,
      shared: shared,
      photoPath: photoPath,
    )!;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
