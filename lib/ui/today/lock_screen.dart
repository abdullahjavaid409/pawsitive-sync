import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Lock-screen preview of a due dose, with quick actions.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.lock,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Text(
                dayLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.lockDate,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                clockLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -3.7,
                  height: 1,
                ),
              ),
              const SizedBox(height: 72),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockCard,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'PAWSITIVESYNC',
                            style: text.bodySmall?.copyWith(
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text('now', style: text.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Miso's evening insulin is due",
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '2 units with food at 8:00 PM. Dan is on tonight.',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockCard,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _Action(
                      label: 'Mark given',
                      color: tokens.brandDark,
                      icon: StrokeIconKind.check,
                      iconColor: tokens.brandDark,
                      onPressed: () =>
                          _done(context, 'Marked given from the lock screen.'),
                    ),
                    _Action(
                      label: 'Snooze 15 minutes',
                      icon: StrokeIconKind.clock,
                      iconColor: scheme.onSurfaceVariant,
                      onPressed: () =>
                          _done(context, 'Snoozed for 15 minutes.'),
                    ),
                    _Action(
                      label: 'Someone else gave it',
                      icon: StrokeIconKind.people,
                      iconColor: scheme.onSurfaceVariant,
                      divider: false,
                      onPressed: () =>
                          _done(context, 'Left for the person on duty.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockHistory,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Sara gave Juniper's supplement",
                              style: text.titleSmall,
                            ),
                            Text(
                              'Evening dose done · 7:41 PM',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 134,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.lockHandle,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _done(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    this.color,
    this.divider = true,
  });

  final String label;
  final StrokeIconKind icon;
  final Color iconColor;
  final VoidCallback onPressed;
  final Color? color;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: scheme.outlineVariant))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
                  color: color ?? scheme.onSurface,
                ),
              ),
            ),
            StrokeIcon(icon, size: 20, color: iconColor),
          ],
        ),
      ),
    );
  }
}
