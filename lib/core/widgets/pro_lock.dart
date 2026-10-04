import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Small "🔒 PRO" pill shown on a Pro-only action for free users, so the
/// lock is visible *before* the tap. Tapping the action opens the paywall
/// for that moment; the pill itself is decoration (no extra tap target).
class ProLock extends StatelessWidget {
  const ProLock({super.key, this.onDark = false});

  /// True on a filled (primary-coloured) button.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = onDark ? scheme.onPrimary : context.paws.brandDark;
    return Semantics(
      label: 'Pro feature',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: onDark
              ? scheme.onPrimary.withValues(alpha: 0.18)
              : context.paws.brandSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StrokeIcon(StrokeIconKind.lock, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(
              'PRO',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] with a [ProLock] after it when [locked].
class WithProLock extends StatelessWidget {
  const WithProLock({
    super.key,
    required this.locked,
    required this.child,
    this.onDark = false,
  });

  final bool locked;
  final Widget child;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: child),
        const SizedBox(width: 8),
        ProLock(onDark: onDark),
      ],
    );
  }
}
