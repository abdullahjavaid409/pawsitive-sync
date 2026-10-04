/// Why the paywall opened — drives contextual copy and analytics.
enum PaywallReason {
  onboarding,
  secondPet,
  invite,
  vetExport,
  milestone,
  settings,

  /// A free user's medicine is running low (refill alerts are Pro).
  refill,

  /// A free solo user marked a dose "not sure if given".
  uncertain,

  /// A free pet already has its maximum number of medicines.
  moreMeds,

  /// A free user picked an afternoon or evening dose time, or moved the
  /// morning reminder out of the morning.
  moreDoseTimes,

  /// A free user asked for history older than the free window.
  history,

  /// Weekly summary notification (Pro).
  weeklySummary,

  /// The recurring idle upgrade prompt on Today.
  weekly,

  /// The daily idle upgrade prompt in a free user's first week.
  firstWeek,
}

extension PaywallReasonQuery on PaywallReason {
  String get queryValue => switch (this) {
    PaywallReason.onboarding => 'onboarding',
    PaywallReason.secondPet => 'second_pet',
    PaywallReason.invite => 'invite',
    PaywallReason.vetExport => 'vet_export',
    PaywallReason.milestone => 'milestone',
    PaywallReason.settings => 'settings',
    PaywallReason.refill => 'refill',
    PaywallReason.uncertain => 'uncertain',
    PaywallReason.moreMeds => 'more_meds',
    PaywallReason.moreDoseTimes => 'more_dose_times',
    PaywallReason.history => 'history',
    PaywallReason.weeklySummary => 'weekly_summary',
    PaywallReason.weekly => 'weekly',
    PaywallReason.firstWeek => 'first_week',
  };

  static PaywallReason? fromQuery(String? raw) {
    return switch (raw) {
      'onboarding' => PaywallReason.onboarding,
      'second_pet' => PaywallReason.secondPet,
      'invite' => PaywallReason.invite,
      'vet_export' => PaywallReason.vetExport,
      'milestone' => PaywallReason.milestone,
      'settings' => PaywallReason.settings,
      'refill' => PaywallReason.refill,
      'uncertain' => PaywallReason.uncertain,
      'more_meds' => PaywallReason.moreMeds,
      'more_dose_times' => PaywallReason.moreDoseTimes,
      'history' => PaywallReason.history,
      'weekly_summary' => PaywallReason.weeklySummary,
      'weekly' => PaywallReason.weekly,
      'first_week' => PaywallReason.firstWeek,
      _ => null,
    };
  }

  /// Pain-first headline + optional subline for this moment.
  (String headline, String? subline) get copy => switch (this) {
    PaywallReason.secondPet => (
      'Every pet deserves the same care',
      'Free covers one pet. Pro keeps every pet’s doses in one list, so nobody gets missed.',
    ),
    PaywallReason.invite => (
      'Did your partner already give it?',
      'No more “did you?” texts. Pro shows everyone who gave each dose, and when.',
    ),
    PaywallReason.vetExport => (
      'Walk into the vet with answers',
      'Pro turns your log into a clear report the vet can read in seconds.',
    ),
    PaywallReason.milestone => (
      'You’ve built a real routine',
      'Now share it, so their care never depends on one person’s memory.',
    ),
    PaywallReason.settings => (
      'Give them your best care',
      'Every pet, every medicine, shared care, refill alerts, and vet reports.',
    ),
    PaywallReason.refill => (
      'Never run out on a Sunday night',
      'Pro warns you before the bottle is empty, while there’s still time to refill.',
    ),
    PaywallReason.uncertain => (
      'Not sure if it was given?',
      'That doubt is the worst part. With Pro, everyone sees who gave each dose.',
    ),
    PaywallReason.moreMeds => (
      'Every medicine, one schedule',
      'Free covers 1 medicine per pet. Pro tracks every one, so no dose is left to memory.',
    ),
    PaywallReason.moreDoseTimes => (
      'Morning and evening, both covered',
      'Free covers one morning dose. Pro adds afternoon and evening reminders at any time, so no dose is forgotten.',
    ),
    PaywallReason.history => (
      'Their whole story, not just a month',
      'Free shows 30 days. Pro keeps the full record, ready when the vet asks “since when?”',
    ),
    PaywallReason.weeklySummary => (
      'Know the week went right',
      'Every Sunday, Pro tells you how many doses were given, so you can relax.',
    ),
    PaywallReason.weekly => (
      'Peace of mind for everyone who cares for them',
      'Every pet and medicine, shared care, full history, and refill alerts.',
    ),
    PaywallReason.firstWeek => (
      'Your first week, done right',
      'Lock in the habit now: every pet, every medicine, everyone who helps.',
    ),
    PaywallReason.onboarding => (
      'Never wonder “did they already get it?”',
      'Two people, one pill, no record: that’s how double doses happen. Pro puts everyone on one list.',
    ),
  };

}
