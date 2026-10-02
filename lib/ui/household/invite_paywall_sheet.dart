import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// Opens the Pro sheet before a free household can send an invite.
Future<bool?> showInvitePaywall(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    sheetAnimationStyle: AppMotion.sheet(context),
    constraints: AdaptiveLayout.sheetConstraints,
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
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 48 + 36 + 40,
              height: 48,
              child: Stack(
                children: [
                  InitialsAvatar(
                    label: 'You',
                    size: 48,
                    fontSize: 14,
                    background: scheme.primary,
                    foreground: scheme.onPrimary,
                    borderColor: scheme.surfaceContainerLowest,
                    borderWidth: 3,
                  ),
                  Positioned(
                    left: 36,
                    child: InitialsAvatar(
                      label: 'S',
                      size: 48,
                      fontSize: 17,
                      background: tokens.brandSoft,
                      foreground: tokens.brandDark,
                      borderColor: scheme.surfaceContainerLowest,
                      borderWidth: 3,
                    ),
                  ),
                  Positioned(
                    left: 76,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(48, 48),
                            painter: DashedCirclePainter(
                              color: scheme.outline,
                              strokeWidth: 2,
                            ),
                          ),
                          StrokeIcon(
                            StrokeIconKind.plus,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Bring Sara onto Miso's schedule",
              style: text.headlineSmall,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Household sync is part of Pro. Everyone sees each dose the moment it's given.",
              style: text.bodyLarge?.copyWith(
                height: 1.45,
                color: AppColors.body,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _CompareTable(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Plan(
                  selected: care.plan == BillingPlan.yearly,
                  title: 'Yearly · Save 50%',
                  price: '\$29.99/yr',
                  onPressed: () => care.setPlan(BillingPlan.yearly),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Plan(
                  selected: care.plan == BillingPlan.monthly,
                  title: 'Monthly',
                  price: '\$4.99/mo',
                  onPressed: () => care.setPlan(BillingPlan.monthly),
                ),
              ),
            ],
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
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
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
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    const rows = [
      ('Caregivers', 'Just you', 'Everyone', false),
      ('Pets', '1', 'Unlimited', false),
      ('Refill alerts', '–', 'Included', true),
      ('Vet PDF report', '–', 'Included', true),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            ColoredBox(
              color: scheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    const Expanded(flex: 14, child: SizedBox()),
                    Expanded(
                      flex: 10,
                      child: Text(
                        'FREE',
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Text(
                        'PRO',
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: tokens.brandDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final row in rows)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: scheme.surfaceContainer),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 14,
                        child: Text(row.$1, style: text.titleSmall),
                      ),
                      Expanded(
                        flex: 10,
                        child: Text(
                          row.$2,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 10,
                        child: Text(
                          row.$3,
                          style: text.titleSmall?.copyWith(
                            color: row.$4 ? tokens.brandDark : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(price, style: text.bodyMedium?.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
