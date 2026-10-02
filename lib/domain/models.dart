enum Species { cat, dog, rabbit, other }

enum MemberRole { owner, caregiver, sitter }

enum DayPart { morning, afternoon, evening }

enum DoseStatus { given, due, upcoming }

enum BillingPlan { yearly, monthly }

enum DoseOutcome { smooth, partial, vomited, lowAppetite }

enum InviteRole { caregiver, sitter }

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
  });

  final String id;
  final String name;
  final String initials;
  final MemberRole role;
  final AvatarTone avatarTone;
  final String? status;
  final bool active;
  final bool isYou;

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

  String get speciesLabel => switch (species) {
    Species.cat => 'Cat',
    Species.dog => 'Dog',
    Species.rabbit => 'Rabbit',
    Species.other => 'Other',
  };
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
    );
  }
}

class Medication {
  const Medication({
    required this.id,
    required this.petId,
    required this.name,
    required this.detail,
    required this.doseLabel,
    required this.whenLabel,
    required this.fallbackLabel,
    required this.dosesLeft,
    required this.supplyTotal,
    required this.lastsUntil,
    required this.onTimeLabel,
    required this.history,
  });

  final String id;
  final String petId;
  final String name;
  final String detail;
  final String doseLabel;
  final String whenLabel;
  final String fallbackLabel;
  final int dosesLeft;
  final int supplyTotal;
  final String lastsUntil;
  final String onTimeLabel;
  final List<DoseLog> history;

  bool get isLow => dosesLeft <= 5;

  Medication copyWith({int? dosesLeft, List<DoseLog>? history}) {
    return Medication(
      id: id,
      petId: petId,
      name: name,
      detail: detail,
      doseLabel: doseLabel,
      whenLabel: whenLabel,
      fallbackLabel: fallbackLabel,
      dosesLeft: dosesLeft ?? this.dosesLeft,
      supplyTotal: supplyTotal,
      lastsUntil: lastsUntil,
      onTimeLabel: onTimeLabel,
      history: history ?? this.history,
    );
  }
}

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
