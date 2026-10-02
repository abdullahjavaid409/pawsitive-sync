/// Why the paywall opened — drives contextual copy and analytics.
enum PaywallReason {
  onboarding,
  secondPet,
  invite,
  vetExport,
  milestone,
  settings,
}

extension PaywallReasonQuery on PaywallReason {
  String get queryValue => switch (this) {
    PaywallReason.onboarding => 'onboarding',
    PaywallReason.secondPet => 'second_pet',
    PaywallReason.invite => 'invite',
    PaywallReason.vetExport => 'vet_export',
    PaywallReason.milestone => 'milestone',
    PaywallReason.settings => 'settings',
  };

  static PaywallReason? fromQuery(String? raw) {
    return switch (raw) {
      'onboarding' => PaywallReason.onboarding,
      'second_pet' => PaywallReason.secondPet,
      'invite' => PaywallReason.invite,
      'vet_export' => PaywallReason.vetExport,
      'milestone' => PaywallReason.milestone,
      'settings' => PaywallReason.settings,
      _ => null,
    };
  }

  /// Pain-first headline + optional subline for this moment.
  (String headline, String? subline) get copy => switch (this) {
    PaywallReason.secondPet => (
      'Track every pet in your household',
      'Free covers one pet. Pro adds up to 10 with the same dose safety.',
    ),
    PaywallReason.invite => (
      'Did your partner or sitter already dose?',
      'Pro syncs one list so nobody double-doses.',
    ),
    PaywallReason.vetExport => (
      'Export a vet-ready dose log',
      'View history free anytime. Pro shares a week-by-week report.',
    ),
    PaywallReason.milestone => (
      'Care with someone else?',
      'You have a solid routine — Pro adds household sync and every pet.',
    ),
    PaywallReason.settings => (
      'Unlock the whole household',
      'Every pet, invites, refill alerts, and vet export.',
    ),
    PaywallReason.onboarding => (
      'Never wonder if someone already gave the dose',
      'Free covers one pet with full dose tracking. Pro unlocks shared care.',
    ),
  };
}
