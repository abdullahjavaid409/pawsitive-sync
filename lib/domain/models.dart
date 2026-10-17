import 'dart:math' as math;

import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/domain/dose_times.dart';

export 'package:pawsitive_sync/domain/dose_times.dart';

enum Species { cat, dog, rabbit, other }

enum MemberRole { owner, caregiver, sitter }

enum DayPart { morning, afternoon, evening }

enum DoseStatus { given, due, upcoming }

enum BillingPlan { yearly, monthly }

enum DoseOutcome { smooth, partial, vomited, lowAppetite }

enum InviteRole { caregiver, sitter }

/// What this phone still owes the server for a pet’s photo (latest wins).
enum PhotoSync { none, upload, remove }

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.initials,
    required this.role,
    required this.avatarTone,
    this.status,
    this.active = false,
    this.isYou = false,
    this.joined = true,
    this.paysForPro = false,
  });

  final String id;
  final String name;
  final String initials;
  final MemberRole role;

  /// Their own subscription is (part of) the household’s Pro. Server-only;
  /// not saved on the phone, so false until the first sync after launch.
  final bool paysForPro;
  final AvatarTone avatarTone;
  final String? status;
  final bool active;
  final bool isYou;

  /// False for people named during setup who have not opened the app yet.
  final bool joined;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'joined': joined,
    if (isYou) 'isYou': true,
    if (paysForPro) 'paysForPro': true,
  };

  String get roleLabel => switch (role) {
    MemberRole.owner => 'Owner',
    MemberRole.caregiver => 'Caregiver',
    MemberRole.sitter => 'Sitter',
  };
}

enum AvatarTone { brand, soft, neutral }

class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.ageYears,
    required this.breed,
    required this.sex,
    required this.conditions,
    required this.weightKg,
    required this.onTimePercent,
    required this.dailyMeds,
    this.photoKey,
    this.photoUrl,
    this.photoVersion = 0,
    this.photoSync = PhotoSync.none,
    this.photoPath,
    this.careNote = '',
    this.careNoteBy = '',
    this.careNoteDay = '',
    this.weights = const [],
  });

  final String id;
  final String name;
  final Species species;
  final int ageYears;
  final String breed;
  final String sex;
  final List<String> conditions;
  final double weightKg;
  final int onTimePercent;
  final int dailyMeds;

  /// Bucket object key of the household’s photo (server truth). Stable, so
  /// it doubles as the on-disk cache key for photos set by other members.
  final String? photoKey;

  /// Short-lived (24h) presigned download URL from the last snapshot.
  /// Never saved: it expires, the key does not.
  final String? photoUrl;

  /// Non-zero while this phone holds its own photo file
  /// (`pet_photos/<id>.jpg`); changes on every new photo so images re-render.
  final int photoVersion;

  /// Pending photo upload or removal, retried on the next sync.
  final PhotoSync photoSync;

  /// Absolute file to show right now, resolved by the repository each run
  /// (the app container path can change between launches, so never saved).
  final String? photoPath;

  bool get hasPhoto => photoPath != null;

  /// Household note shown on the pet's profile ("Give insulin only after
  /// she has eaten"). Empty when there is none.
  final String careNote;

  /// Member id of whoever last wrote [careNote].
  final String careNoteBy;

  /// Local day [careNote] was last written, YYYY-MM-DD.
  final String careNoteDay;

  /// Weigh-ins, oldest first, at most [maxWeights]. Grows when the weight
  /// changes; drives the weight chart on Reports.
  final List<WeightEntry> weights;

  static const maxWeights = 24;

  /// Longest household note, matching the server's limit.
  static const maxNoteLength = 280;

  String get speciesLabel => switch (species) {
    Species.cat => 'Cat',
    Species.dog => 'Dog',
    Species.rabbit => 'Rabbit',
    Species.other => 'Other',
  };

  /// What the API accepts for create/update. Photo fields have their own
  /// endpoints and are never sent here. The household note goes only with
  /// note edits ([withNote]), so an offline profile edit can't overwrite a
  /// note a partner wrote meanwhile (the server keeps what it has).
  Map<String, Object?> toJson({bool withNote = false}) => {
    'id': id,
    'name': name,
    'species': species.name,
    'ageYears': ageYears,
    'weightKg': weightKg,
    'breed': breed,
    'sex': sex,
    'conditions': conditions,
    if (withNote) ...{
      'careNote': careNote,
      'careNoteBy': careNoteBy,
      'careNoteDay': careNoteDay,
    },
    // Weigh-ins change with the weight, on the same edit.
    'weights': [for (final w in weights) w.toJson()],
  };

  /// [toJson] plus this phone’s photo state, for the local store only.
  Map<String, Object?> toStoreJson() => {
    ...toJson(withNote: true),
    if (photoKey != null) 'photoKey': photoKey,
    if (photoVersion != 0) 'photoVersion': photoVersion,
    if (photoSync != PhotoSync.none) 'photoSync': photoSync.name,
  };

  Pet copyWith({
    String? name,
    Species? species,
    int? ageYears,
    String? breed,
    String? sex,
    List<String>? conditions,
    double? weightKg,
    int? onTimePercent,
    int? dailyMeds,
    String? careNote,
    String? careNoteBy,
    String? careNoteDay,
    List<WeightEntry>? weights,
  }) {
    return Pet(
      id: id,
      name: name ?? this.name,
      species: species ?? this.species,
      ageYears: ageYears ?? this.ageYears,
      breed: breed ?? this.breed,
      sex: sex ?? this.sex,
      conditions: conditions ?? this.conditions,
      weightKg: weightKg ?? this.weightKg,
      onTimePercent: onTimePercent ?? this.onTimePercent,
      dailyMeds: dailyMeds ?? this.dailyMeds,
      photoKey: photoKey,
      photoUrl: photoUrl,
      photoVersion: photoVersion,
      photoSync: photoSync,
      photoPath: photoPath,
      careNote: careNote ?? this.careNote,
      careNoteBy: careNoteBy ?? this.careNoteBy,
      careNoteDay: careNoteDay ?? this.careNoteDay,
      weights: weights ?? this.weights,
    );
  }

  static const _keep = Object();

  /// Changes only the photo fields; pass null to clear a nullable one.
  Pet withPhoto({
    Object? photoKey = _keep,
    Object? photoUrl = _keep,
    int? photoVersion,
    PhotoSync? photoSync,
    Object? photoPath = _keep,
  }) {
    return Pet(
      id: id,
      name: name,
      species: species,
      ageYears: ageYears,
      breed: breed,
      sex: sex,
      conditions: conditions,
      weightKg: weightKg,
      onTimePercent: onTimePercent,
      dailyMeds: dailyMeds,
      photoKey: identical(photoKey, _keep)
          ? this.photoKey
          : photoKey as String?,
      photoUrl: identical(photoUrl, _keep)
          ? this.photoUrl
          : photoUrl as String?,
      photoVersion: photoVersion ?? this.photoVersion,
      photoSync: photoSync ?? this.photoSync,
      photoPath: identical(photoPath, _keep)
          ? this.photoPath
          : photoPath as String?,
      careNote: careNote,
      careNoteBy: careNoteBy,
      careNoteDay: careNoteDay,
      weights: weights,
    );
  }
}

/// One weigh-in: the local day and kilograms.
class WeightEntry {
  const WeightEntry({required this.day, required this.kg});

  /// YYYY-MM-DD.
  final String day;
  final double kg;

  Map<String, Object?> toJson() => {'day': day, 'kg': kg};

  /// Null for junk (bad day or weight), so one bad row never breaks a pet.
  static WeightEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final day = raw['day'];
    final kg = raw['kg'];
    if (day is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      return null;
    }
    final value = kg is num ? kg.toDouble() : double.tryParse('$kg');
    if (value == null || value <= 0 || value >= 100) return null;
    return WeightEntry(day: day, kg: value);
  }

  @override
  bool operator ==(Object other) =>
      other is WeightEntry && other.day == day && other.kg == kg;

  @override
  int get hashCode => Object.hash(day, kg);
}

class Dose {
  const Dose({
    required this.id,
    required this.petId,
    required this.medicationId,
    required this.name,
    required this.amount,
    required this.part,
    required this.status,
    required this.subtitle,
    this.givenById,
    this.givenAt = '',
    int? minute,
  }) : minute = minute ?? -1;

  final String id;
  final String petId;
  final String medicationId;
  final String name;
  final String amount;
  final DayPart part;
  final DoseStatus status;
  final String subtitle;
  final String? givenById;

  /// Time the logged dose was given, e.g. "8:02 AM". Empty when not logged.
  final String givenAt;

  /// Scheduled reminder time (minute of day); the part’s default when the
  /// medicine has no custom time.
  final int minute;

  /// "7:00 AM" — the scheduled time as the phone shows clocks.
  String get timeLabel =>
      ClockFormat.label(minute < 0 ? part.defaultMinute : minute);

  String get title => amount.isEmpty ? name : '$name · $amount';

  Dose copyWith({
    DoseStatus? status,
    String? subtitle,
    String? givenById,
    String? amount,
  }) {
    return Dose(
      id: id,
      petId: petId,
      medicationId: medicationId,
      name: name,
      amount: amount ?? this.amount,
      part: part,
      status: status ?? this.status,
      subtitle: subtitle ?? this.subtitle,
      givenById: givenById ?? this.givenById,
      givenAt: givenAt,
      minute: minute,
    );
  }
}

/// A repeating medicine: what it is and which parts of the day it is given.
class Medication {
  const Medication({
    required this.id,
    required this.petId,
    required this.name,
    required this.amount,
    required this.parts,
    required this.supplyTotal,
    required this.dosesLeft,
    required this.startDay,
    this.endDay = '',
    this.archivedAt,
    this.times = const {},
    this.needsPro = false,
    this.everyDays = 1,
    this.withFood = false,
    this.site = '',
  });

  final String id;
  final String petId;
  final String name;
  final String amount;
  final List<DayPart> parts;

  /// How often it repeats, counted from [startDay]: 1 every day, 2 every
  /// other day, 7 once a week (on [startDay]'s weekday).
  final int everyDays;

  /// "Give with food": shown on every dose so nobody forgets.
  final bool withFood;

  /// Where it's given for drops and topicals ("Left eye"); empty otherwise.
  final String site;

  /// Allowed values of [everyDays].
  static const repeatOptions = [1, 2, 7];

  /// Custom reminder time per part (minute of day). Missing parts use the
  /// part’s default; see [DoseTimes] for the rules.
  final Map<DayPart, int> times;

  /// Reminder time for [part] as a minute of day.
  int minuteFor(DayPart part) => times[part] ?? part.defaultMinute;

  /// From this minute of the day on the dose counts as due: the part’s
  /// usual opening ([DayPartLabel.opensAt]) or the custom time when earlier,
  /// so a 15:00 "evening" dose is due at 15:00, never shown as upcoming
  /// after its own reminder fired.
  int dueFromMinute(DayPart part) =>
      math.min(part.opensAt * 60, minuteFor(part));

  /// "7:00 AM" for [part], in the phone’s clock format.
  String timeLabelFor(DayPart part) => ClockFormat.label(minuteFor(part));

  /// True when any selected part has a non-default time.
  bool get hasCustomTimes => parts.any((part) => times[part] != null);

  /// 0 means the supply is not tracked.
  final int supplyTotal;
  final int dosesLeft;

  /// Local calendar day the schedule started, as YYYY-MM-DD.
  final String startDay;

  /// Last day to give this medicine, or empty when ongoing.
  final String endDay;

  /// When the medicine was stopped (removed from the household), as an ISO
  /// timestamp or YYYY-MM-DD; null while it is on the schedule. Stopped
  /// medicines are kept only to label their dose history.
  final String? archivedAt;

  bool get isArchived => archivedAt != null;

  /// The server saved it over Free’s limits (old or modified app, or Pro
  /// that ended before an offline add synced). Never set by this phone;
  /// cleared by the server once the household has Pro. Doses still log;
  /// reminders wait for Pro (see [CareRepository.isMedicationLocked]).
  final bool needsPro;

  /// "Oct 2" — the local day it was stopped, or empty while active.
  String get stoppedDayLabel {
    final raw = archivedAt;
    if (raw == null) return '';
    final at = (DateTime.tryParse(raw) ?? DateTime.tryParse(endDay))?.toLocal();
    if (at == null) return '';
    return '${_months[at.month - 1]} ${at.day}';
  }

  /// The name as history shows it: "Antibiotic (stopped Oct 2)" once stopped.
  String get historyName {
    if (!isArchived) return name;
    final day = stoppedDayLabel;
    return day.isEmpty ? '$name (stopped)' : '$name (stopped $day)';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Scheduled on [day] (YYYY-MM-DD): inside the course and, for every-2-
  /// days or weekly medicines, on one of its repeat days. Every schedule in
  /// the app (Today, reminders, reports, widgets) asks this one question.
  bool isActiveOn(String day) {
    if (startDay.compareTo(day) > 0) return false;
    if (endDay.isNotEmpty && endDay.compareTo(day) < 0) return false;
    if (everyDays <= 1) return true;
    final start = DateTime.tryParse(startDay);
    final date = DateTime.tryParse(day);
    // Unreadable days fall back to "every day": a reminder too many beats a
    // silently skipped dose.
    if (start == null || date == null) return true;
    // UTC midnights: whole days, no DST hour drifting the count.
    final days = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return days % everyDays == 0;
  }

  bool get endsSoon {
    if (endDay.isEmpty) return false;
    final end = DateTime.tryParse(endDay);
    if (end == null) return false;
    final today = DateTime.now();
    final diff = end
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    return diff >= 0 && diff <= 3;
  }

  bool get tracksSupply => supplyTotal > 0;

  /// Low when about three days' worth (by count) is left.
  bool get isLow => tracksSupply && dosesLeft <= (parts.length * 3).clamp(3, 9);

  double get supplyFraction =>
      tracksSupply ? (dosesLeft / supplyTotal).clamp(0.0, 1.0) : 0;

  String get doseLabel => amount.isEmpty ? 'As prescribed' : amount;

  /// "Morning 7:00 AM & evening 7:00 PM" — parts with their times.
  String get timesLabel {
    if (parts.isEmpty) return '';
    final items = [
      for (final (i, part) in parts.indexed)
        '${i == 0 ? part.label : part.label.toLowerCase()} ${timeLabelFor(part)}',
    ];
    if (items.length == 1) return items.single;
    return '${items.take(items.length - 1).join(', ')} & ${items.last}';
  }

  /// "Every 2 days", "Mondays", or empty for every day.
  String get repeatLabel {
    if (everyDays <= 1) return '';
    if (everyDays == 7) {
      final start = DateTime.tryParse(startDay);
      if (start == null) return 'Once a week';
      const names = [
        'Mondays',
        'Tuesdays',
        'Wednesdays',
        'Thursdays',
        'Fridays',
        'Saturdays',
        'Sundays',
      ];
      return names[start.weekday - 1];
    }
    return 'Every $everyDays days';
  }

  String get whenLabel {
    if (parts.isEmpty) return '';
    if (everyDays > 1) {
      final at = [for (final p in parts) p.label.toLowerCase()].join(' & ');
      return '$repeatLabel · $at';
    }
    if (parts.length == 1) return 'Every ${parts.first.label.toLowerCase()}';
    final rest = [for (final part in parts.skip(1)) part.label.toLowerCase()];
    final head = [parts.first.label, ...rest.take(rest.length - 1)].join(', ');
    return '$head & ${rest.last}';
  }

  /// "2 drops · Left eye" — the amount and where it goes.
  String get doseWithSite =>
      [if (amount.isNotEmpty) amount, if (site.isNotEmpty) site].join(' · ');

  String get detail => [
    if (doseWithSite.isNotEmpty) doseWithSite,
    whenLabel,
    if (withFood) 'with food',
  ].join(' · ');

  /// Rough last day of supply, or empty when supply is not tracked.
  String lastsUntil(DateTime now) {
    if (!tracksSupply || parts.isEmpty) return '';
    // Doses per active day, spread over every-N-day repeats.
    final days = dosesLeft ~/ parts.length * (everyDays < 1 ? 1 : everyDays);
    final end = DateTime(now.year, now.month, now.day + days);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[end.weekday - 1]}, ${months[end.month - 1]} ${end.day}';
  }

  Medication copyWith({
    int? dosesLeft,
    String? endDay,
    String? archivedAt,
    Map<DayPart, int>? times,
    bool? needsPro,
  }) {
    return Medication(
      id: id,
      petId: petId,
      name: name,
      amount: amount,
      parts: parts,
      supplyTotal: supplyTotal,
      dosesLeft: dosesLeft ?? this.dosesLeft,
      startDay: startDay,
      endDay: endDay ?? this.endDay,
      archivedAt: archivedAt ?? this.archivedAt,
      times: times ?? this.times,
      needsPro: needsPro ?? this.needsPro,
      everyDays: everyDays,
      withFood: withFood,
      site: site,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'petId': petId,
    'name': name,
    'amount': amount,
    'parts': [for (final part in parts) part.name],
    'supplyTotal': supplyTotal,
    'dosesLeft': dosesLeft,
    'startDay': startDay,
    if (endDay.isNotEmpty) 'endDay': endDay,
    // Absent (not empty) when there are no custom times: the server keeps
    // what it has when the field is missing, so a replayed add can’t wipe
    // times set later on another phone.
    if (times.isNotEmpty) 'times': DoseTimes.encode(times),
    // Read back from saved data; the server ignores it and decides itself.
    if (needsPro) 'needsPro': true,
    // Additive; older servers ignore them and treat it as every day.
    if (everyDays != 1) 'everyDays': everyDays,
    if (withFood) 'withFood': true,
    if (site.isNotEmpty) 'site': site,
  };
}

enum LogOutcome { given, skipped, uncertain }

enum CareEventKind { vaccine, vetVisit, refill, other }

extension CareEventKindLabel on CareEventKind {
  String get kindLabel => switch (this) {
    CareEventKind.vaccine => 'Vaccine',
    CareEventKind.vetVisit => 'Vet visit',
    CareEventKind.refill => 'Refill',
    CareEventKind.other => 'Care',
  };
}

/// A vet visit, vaccine due date, or other care milestone.
class CareEvent {
  const CareEvent({
    required this.id,
    required this.petId,
    required this.title,
    required this.kind,
    required this.dueDay,
    this.note = '',
  });

  final String id;
  final String petId;
  final String title;
  final CareEventKind kind;
  final String dueDay;
  final String note;

  String get kindLabel => kind.kindLabel;

  Map<String, Object?> toJson() => {
    'id': id,
    'petId': petId,
    'title': title,
    'kind': kind.name,
    'dueDay': dueDay,
    'note': note,
  };

  static CareEvent fromJson(Map<String, dynamic> json) => CareEvent(
    id: '${json['id']}',
    petId: '${json['petId']}',
    title: '${json['title']}',
    kind: CareEventKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => CareEventKind.other,
    ),
    dueDay: '${json['dueDay']}',
    note: '${json['note'] ?? ''}',
  );
}

/// One saved dose: who gave (or skipped) which medicine, on which day and time of day.
class DoseRecord {
  const DoseRecord({
    required this.id,
    required this.medicationId,
    required this.part,
    required this.day,
    required this.memberId,
    required this.outcome,
    required this.amount,
    required this.timeLabel,
    this.note,
  });

  final String id;
  final String medicationId;
  final DayPart part;
  final String day;
  final String memberId;
  final LogOutcome outcome;
  final String amount;
  final String timeLabel;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'medicationId': medicationId,
    'part': part.name,
    'day': day,
    'memberId': memberId,
    'outcome': outcome.name,
    'amount': amount,
    'timeLabel': timeLabel,
    if (note != null) 'note': note,
  };
}

extension DayPartLabel on DayPart {
  String get label => switch (this) {
    DayPart.morning => 'Morning',
    DayPart.afternoon => 'Afternoon',
    DayPart.evening => 'Evening',
  };

  /// Default reminder time for this part of the day.
  int get hour => switch (this) {
    DayPart.morning => 8,
    DayPart.afternoon => 13,
    DayPart.evening => 20,
  };

  /// [hour] as a minute of day.
  int get defaultMinute => hour * 60;

  /// From this hour on, the dose counts as due.
  int get opensAt => switch (this) {
    DayPart.morning => 0,
    DayPart.afternoon => 12,
    DayPart.evening => 17,
  };

  /// The default time ("8:00 AM"); use [Medication.timeLabelFor] or
  /// [Dose.timeLabel] wherever a medicine is known.
  String get timeLabel => ClockFormat.label(defaultMinute);
}

/// One past dose of a medicine, ready to show.
class DoseLog {
  const DoseLog({required this.when, required this.who, this.lateNote});

  final String when;
  final String who;
  final String? lateNote;
}

class ActivityItem {
  const ActivityItem({
    required this.memberId,
    required this.actor,
    required this.action,
    required this.emphasis,
    required this.timeLabel,
    this.note,
    this.dayLabel = '',
    this.time = '',
    this.outcome = LogOutcome.given,
  });

  final String memberId;
  final String actor;
  final String action;
  final String emphasis;

  /// "8:02 AM" today, "Yesterday · 8:02 AM" before: for one-line uses.
  final String timeLabel;
  final String? note;

  /// "Today", "Yesterday" or a short date: the group an activity list
  /// files this row under.
  final String dayLabel;

  /// Clock time alone ("8:02 AM"), shown inside its day group.
  final String time;
  final LogOutcome outcome;
}
