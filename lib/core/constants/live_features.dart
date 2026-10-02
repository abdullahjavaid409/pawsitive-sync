/// Canonical list of every **live** product feature and its required logs.
/// Used by [live_features_coverage_test.dart] — do not ship UI from here.
abstract final class LiveFeatures {
  static const version = '1.0.0';

  /// Repository + service logs that must be exercised in automated tests.
  static const coverage = <LiveFeatureSpec>[
    LiveFeatureSpec(
      id: 'dose_log',
      name: 'Log dose (free)',
      tier: FeatureTier.free,
      logs: ['dose.log.completed', 'dose.log.rejected'],
    ),
    LiveFeatureSpec(
      id: 'dose_uncertain',
      name: 'Not sure if given (free)',
      tier: FeatureTier.free,
      logs: ['dose.uncertain.completed'],
    ),
    LiveFeatureSpec(
      id: 'dose_skip',
      name: 'Skip dose (free)',
      tier: FeatureTier.free,
      logs: ['dose.skip.completed'],
    ),
    LiveFeatureSpec(
      id: 'pet_add',
      name: 'Add pet',
      tier: FeatureTier.free,
      logs: ['pet.add.completed', 'pet.add_rejected', 'pet.add.blocked'],
    ),
    LiveFeatureSpec(
      id: 'pet_update',
      name: 'Edit pet',
      tier: FeatureTier.free,
      logs: ['pet.update.completed', 'pet.update.missing', 'pet.update.noop'],
    ),
    LiveFeatureSpec(
      id: 'medication',
      name: 'Add / refill / stop medicine',
      tier: FeatureTier.free,
      logs: [
        'medication.add.completed',
        'medication.add_rejected',
        'medication.refill.completed',
        'medication.remove.completed',
      ],
    ),
    LiveFeatureSpec(
      id: 'care_events',
      name: 'Coming up — vet / vaccine / refill',
      tier: FeatureTier.free,
      logs: ['care_event.added', 'care_event.rejected', 'care_event.removed'],
    ),
    LiveFeatureSpec(
      id: 'vet_report_view',
      name: 'Vet report view (free)',
      tier: FeatureTier.free,
      logs: [],
    ),
    LiveFeatureSpec(
      id: 'household_connect',
      name: 'Share household online',
      tier: FeatureTier.pro,
      logs: ['household.connected', 'household.connect_skipped'],
    ),
    LiveFeatureSpec(
      id: 'household_join',
      name: 'Join with invite code',
      tier: FeatureTier.pro,
      logs: ['household.joined', 'household.join_rejected', 'household.join_skipped'],
    ),
    LiveFeatureSpec(
      id: 'household_sync',
      name: 'Pull household state',
      tier: FeatureTier.pro,
      logs: ['household.synced', 'household.sync_skipped', 'household.sync_failed'],
    ),
    LiveFeatureSpec(
      id: 'sitter_browser',
      name: 'Browser sitter link (no app)',
      tier: FeatureTier.pro,
      logs: [
        'sitter.link_ready',
        'sitter.link_cached',
        'sitter.link_skipped',
        'sitter.link_failed',
      ],
    ),
    LiveFeatureSpec(
      id: 'partner_push',
      name: 'Notify when partner logs',
      tier: FeatureTier.pro,
      logs: [
        'push.partner_detected',
        'push.partner_skipped',
        'push.register_skipped',
        'push.preference',
      ],
    ),
    LiveFeatureSpec(
      id: 'pro_gates',
      name: 'Pro unlocks invites / multi-pet / export / low supply',
      tier: FeatureTier.pro,
      logs: ['billing.pro.unlocked', 'household.reset'],
    ),
    LiveFeatureSpec(
      id: 'billing',
      name: 'Plan + restore',
      tier: FeatureTier.free,
      logs: ['billing.plan.changed', 'billing.restore.requested', 'billing.restore.skipped'],
    ),
    LiveFeatureSpec(
      id: 'onboarding',
      name: 'First-run setup',
      tier: FeatureTier.free,
      logs: ['household.created_from_onboarding'],
    ),
  ];

  /// Flat list of every log string tests must hit at least once.
  static List<String> get allRequiredLogs {
    final seen = <String>{};
    final out = <String>[];
    for (final feature in coverage) {
      for (final log in feature.logs) {
        if (seen.add(log)) out.add(log);
      }
    }
    return out;
  }
}

enum FeatureTier { free, pro }

class LiveFeatureSpec {
  const LiveFeatureSpec({
    required this.id,
    required this.name,
    required this.tier,
    required this.logs,
  });

  final String id;
  final String name;
  final FeatureTier tier;
  final List<String> logs;
}
