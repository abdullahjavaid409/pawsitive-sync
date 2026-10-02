import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

Future<bool?> showInvitePaywall(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _InvitePaywall(),
  );
}

class _InvitePaywall extends StatelessWidget {
  const _InvitePaywall();

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InitialsAvatar(
                label: 'You',
                size: 40,
                fontSize: 12,
                background: scheme.primary,
                foreground: scheme.onPrimary,
              ),
              const SizedBox(width: 8),
              InitialsAvatar(
                label: 'S',
                size: 40,
                background: tokens.brandSoft,
                foreground: tokens.brandDark,
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline),
                ),
                child: StrokeIcon(
                  StrokeIconKind.plus,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Bring Sara onto Miso's schedule",
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Household sync is part of Pro. Everyone sees each dose the moment it's given.",
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const _CompareTable(),
          const SizedBox(height: 16),
          _Plan(
            selected: care.plan == BillingPlan.yearly,
            title: 'Yearly · Save 50%',
            price: '\$29.99/yr',
            onPressed: () => care.setPlan(BillingPlan.yearly),
          ),
          const SizedBox(height: 8),
          _Plan(
            selected: care.plan == BillingPlan.monthly,
            title: 'Monthly',
            price: '\$4.99/mo',
            onPressed: () => care.setPlan(BillingPlan.monthly),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              care.startTrial();
              Navigator.of(context).pop(true);
            },
            child: const Text('Try Pro free for 7 days'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      ('', 'FREE', 'PRO'),
      ('Caregivers', 'Just you', 'Everyone'),
      ('Pets', '1', 'Unlimited'),
      ('Refill alerts', '–', 'Included'),
      ('Vet PDF report', '–', 'Included'),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    row.$1,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$3,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.selected,
    required this.title,
    required this.price,
    required this.onPressed,
  });

  final bool selected;
  final String title;
  final String price;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(price, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
