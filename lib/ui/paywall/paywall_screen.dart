import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Offers a free trial and a free path that keeps one pet.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final onboarding = context.read<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = onboarding.petName.trim().isEmpty
        ? 'them'
        : onboarding.petName.trim();
    final priceLine = care.plan == BillingPlan.yearly
        ? 'No charge today. Then \$29.99 per year.'
        : 'No charge today. Then \$4.99 per month.';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close and continue free',
                    onPressed: () => _enter(context, trial: false),
                    icon: StrokeIcon(
                      StrokeIconKind.close,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No purchase on this phone to restore.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Restore'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Care for $name together.',
                      style: text.displaySmall?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try every Pro feature free. Cancel anytime.',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    _TimelineStep(
                      title: 'Today',
                      body: 'Household sync, refill alerts, vet reports, unlimited pets',
                      done: true,
                      showLine: true,
                    ),
                    _TimelineStep(
                      title: 'Day 5',
                      body: 'We remind you before the trial ends',
                      done: false,
                      showLine: true,
                      icon: StrokeIconKind.bell,
                    ),
                    _TimelineStep(
                      title: 'Day 7',
                      body: 'Your plan starts. Cancel before and pay nothing.',
                      done: false,
                      showLine: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    _PlanTile(
                      selected: care.plan == BillingPlan.yearly,
                      title: 'Yearly',
                      subtitle: '\$29.99 per year',
                      price: '\$2.50/mo',
                      badge: 'Save 50%',
                      onPressed: () => care.setPlan(BillingPlan.yearly),
                    ),
                    const SizedBox(height: 8),
                    _PlanTile(
                      selected: care.plan == BillingPlan.monthly,
                      title: 'Monthly',
                      price: '\$4.99/mo',
                      onPressed: () => care.setPlan(BillingPlan.monthly),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: () => _enter(context, trial: true),
                      child: const Text('Start 7-day free trial'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      priceLine,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('Terms'),
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text('Privacy'),
                        ),
                        TextButton(
                          onPressed: () => _enter(context, trial: false),
                          child: const Text('Continue free with 1 pet'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enter(BuildContext context, {required bool trial}) {
    if (trial) context.read<CareRepository>().startTrial();
    context.read<OnboardingViewModel>().finish(reminders: true);
    context.go(AppRoutes.today);
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.body,
    required this.done,
    required this.showLine,
    this.icon,
  });

  final String title;
  final String body;
  final bool done;
  final bool showLine;
  final StrokeIconKind? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done
                        ? scheme.primary
                        : scheme.surfaceContainerLowest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done || icon != null
                          ? scheme.primary
                          : scheme.outline,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? StrokeIcon(
                          StrokeIconKind.check,
                          size: 14,
                          color: scheme.onPrimary,
                        )
                      : icon == null
                      ? null
                      : StrokeIcon(icon!, size: 12, color: scheme.primary),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
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
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: selected ? 72 : 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                        mainAxisAlignment: MainAxisAlignment.center,
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
