import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/legal/subscription_disclosure.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Compares Free and Pro. Free is one pet. Pro is the whole household.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const _proFeatures = [
    (
      'Today\'s dose list',
      'See every medicine due today — morning, afternoon, and evening — for all your pets in one place.',
    ),
    (
      'One tap to log',
      'Tap a dose and record who gave it, so the same medicine is never given twice.',
    ),
    (
      'Smart reminders',
      'Get notified when a dose is due, even when someone else is caring for your pet.',
    ),
    (
      'Every pet',
      'Track schedules for cats, dogs, rabbits, and more — not just one pet.',
    ),
    (
      'Shared household',
      'Your partner, sitter, or family see the same list and who already gave each dose.',
    ),
    (
      'Running-low alerts',
      'We warn you before the bottle runs out so refills do not slip through the cracks.',
    ),
    (
      'Vet reports',
      'Export a clear week-by-week log to share at checkups or send ahead to the clinic.',
    ),
    (
      'Sync across phones',
      'Join with an invite code and everyone stays on the same schedule, online or off.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final care = context.read<CareRepository>();
      if (care.plan != BillingPlan.yearly) {
        care.setPlan(BillingPlan.yearly);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final yearly = care.plan == BillingPlan.yearly;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Continue free',
                  onPressed: () => _enter(context, trial: false),
                  icon: StrokeIcon(
                    StrokeIconKind.close,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    AppLog.event('billing.restore');
                    await launchUrl(
                      Uri.parse(AppLinks.manageAppleSubscriptions),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text('Restore'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                children: [
                  Text('Try Pro free for 7 days', style: text.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a plan. Yearly saves the most.',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PlanTile(
                    selected: yearly,
                    title: 'Yearly',
                    subtitle: '\$29.99 per year',
                    price: '\$2.50/mo',
                    badge: 'Save 50%',
                    onPressed: () => care.setPlan(BillingPlan.yearly),
                  ),
                  const SizedBox(height: 8),
                  _PlanTile(
                    selected: !yearly,
                    title: 'Monthly',
                    price: '\$4.99/mo',
                    onPressed: () => care.setPlan(BillingPlan.monthly),
                  ),
                  const SizedBox(height: 24),
                  Text('What you get with Pro', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Free covers one pet. Pro unlocks everything below.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tokens.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        children: [
                          for (final (index, feature) in _proFeatures.indexed)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _proFeatures.length - 1
                                    ? 0
                                    : 16,
                              ),
                              child: _FeatureRow(
                                title: feature.$1,
                                detail: feature.$2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Free stays on one pet with local reminders.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: () => _enter(context, trial: true),
                    child: Text(
                      yearly
                          ? 'Start 7-day free trial · Yearly'
                          : 'Start 7-day free trial · Monthly',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    SubscriptionDisclosure.compactLine(care.plan),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => _enter(context, trial: false),
                    child: const Text('Continue free with 1 pet'),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(AppLinks.terms),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Terms'),
                      ),
                      Text(
                        '·',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(AppLinks.privacy),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Privacy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enter(BuildContext context, {required bool trial}) async {
    final care = context.read<CareRepository>();
    final model = context.read<OnboardingViewModel>();
    if (trial) {
      care.startTrial();
    } else {
      AppLog.event('billing.continued_free');
    }
    care.applyOnboarding(model);
    await model.finish(reminders: model.remindersOn);
    if (!context.mounted) return;
    if (model.remindersOn) {
      DoseReminders.scheduleNext(care);
    } else {
      DoseReminders.cancel();
    }
    context.go(AppRoutes.today);
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: StrokeIcon(
            StrokeIconKind.check,
            size: 18,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: 2),
              Text(
                detail,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.selected,
    required this.title,
    required this.price,
    required this.onPressed,
    this.subtitle,
    this.badge,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final String price;
  final String? badge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outline,
                        width: selected ? 6 : 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  Text(price, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -11,
            right: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  badge!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
