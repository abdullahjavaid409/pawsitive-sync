import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Compares Free and Pro. Free is one pet. Pro is the whole household.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  static const _rows = [
    ('Today\'s list', true, true),
    ('I gave this', true, true),
    ('A reminder', true, true),
    ('One pet', true, true),
    ('Every pet', false, true),
    ('Invite the family', false, true),
    ('Running low', false, true),
    ('For the vet', false, true),
  ];

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final priceLine = care.plan == BillingPlan.yearly
        ? 'No charge today. Then \$29.99 per year.'
        : 'No charge today. Then \$4.99 per month.';

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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No purchase on this phone to restore.'),
                      ),
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
                  Text('Pro vs Free', style: text.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Free is for one pet. Pro is for everyone who helps.',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tokens.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                        children: [
                          _CompareRow(
                            label: '',
                            free: false,
                            pro: false,
                            header: true,
                          ),
                          for (final row in _rows)
                            _CompareRow(
                              label: row.$1,
                              free: row.$2,
                              pro: row.$3,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: () => _enter(context, trial: true),
                    child: const Text('Start 7-day free trial'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    priceLine,
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => _enter(context, trial: false),
                    child: const Text('Continue free with 1 pet'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _enter(BuildContext context, {required bool trial}) {
    final care = context.read<CareRepository>();
    final model = context.read<OnboardingViewModel>();
    if (trial) care.startTrial();
    model.finish(reminders: model.remindersOn);
    if (model.remindersOn) {
      DoseReminders.scheduleNext(care);
    } else {
      DoseReminders.cancel();
    }
    context.go(AppRoutes.today);
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.free,
    required this.pro,
    this.header = false,
  });

  final String label;
  final bool free;
  final bool pro;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: header ? text.bodyMedium : text.titleSmall,
            ),
          ),
          SizedBox(
            width: 52,
            child: header
                ? Text(
                    'Free',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : _Mark(included: free, color: scheme.onSurfaceVariant),
          ),
          SizedBox(
            width: 52,
            child: header
                ? Text(
                    'Pro',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : _Mark(included: pro, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.included, required this.color});

  final bool included;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!included) {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return Center(
      child: StrokeIcon(StrokeIconKind.check, size: 18, color: color),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        Text(title, style: Theme.of(context).textTheme.titleMedium),
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
