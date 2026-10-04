enum Species { cat, dog, rabbit, other }

enum MemberRole { owner, caregiver, sitter }

enum DayPart { morning, afternoon, evening }

enum DoseStatus { given, due, upcoming }

enum BillingPlan { yearly, monthly }

enum DoseOutcome { smooth, partial, vomited, lowAppetite }

enum InviteRole { caregiver, sitter }

/// What this phone still owes the server for a pet's photo (latest wins).
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

  /// Their own subscription is (part of) the household's Pro. Server-only;
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

  /// Bucket object key of the household's photo (server truth). Stable, so
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

  String get speciesLabel => switch (species) {
    Species.cat => 'Cat',
    Species.dog => 'Dog',
    Species.rabbit => 'Rabbit',
    Species.other => 'Other',
  };

  /// What the API accepts for create/update. Photo fields have their own
  /// endpoints and are never sent here.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'species': species.name,
    'ageYears': ageYears,
    'weightKg': weightKg,
    'breed': breed,
    'sex': sex,
    'conditions': conditions,
  };

  /// [toJson] plus this phone's photo state, for the local store only.
  Map<String, Object?> toStoreJson() => {
    ...toJson(),
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
    );
  }
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
  });

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
  });

  final String id;
  final String petId;
  final String name;
  final String amount;
  final List<DayPart> parts;

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

  bool isActiveOn(String day) =>
      startDay.compareTo(day) <= 0 &&
      (endDay.isEmpty || endDay.compareTo(day) >= 0);

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

  bool get isLow => tracksSupply && dosesLeft <= (parts.length * 3).clamp(3, 9);

  double get supplyFraction =>
      tracksSupply ? (dosesLeft / supplyTotal).clamp(0.0, 1.0) : 0;

  String get doseLabel => amount.isEmpty ? 'As prescribed' : amount;

  String get whenLabel {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return 'Every ${parts.first.label.toLowerCase()}';
    final rest = [for (final part in parts.skip(1)) part.label.toLowerCase()];
    final head = [parts.first.label, ...rest.take(rest.length - 1)].join(', ');
    return '$head & ${rest.last}';
  }

  String get detail => [if (amount.isNotEmpty) amount, whenLabel].join(' · ');

  /// Rough last day of supply, or empty when supply is not tracked.
  String lastsUntil(DateTime now) {
    if (!tracksSupply || parts.isEmpty) return '';
    final days = dosesLeft ~/ parts.length;
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

  Medication copyWith({int? dosesLeft, String? endDay, String? archivedAt}) {
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

  /// From this hour on, the dose counts as due.
  int get opensAt => switch (this) {
    DayPart.morning => 0,
    DayPart.afternoon => 12,
    DayPart.evening => 17,
  };

  String get timeLabel => switch (this) {
    DayPart.morning => '8:00 AM',
    DayPart.afternoon => '1:00 PM',
    DayPart.evening => '8:00 PM',
  };
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
  });

  final String memberId;
  final String actor;
  final String action;
  final String emphasis;
  final String timeLabel;
  final String? note;
}
