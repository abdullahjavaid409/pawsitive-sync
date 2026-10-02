import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.size = 30,
    this.fontSize = 13,
    this.borderColor,
    this.showPresence = false,
    this.dashed = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double size;
  final double fontSize;
  final Color? borderColor;
  final bool showPresence;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final ring = borderColor;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : background,
            shape: BoxShape.circle,
            border: ring == null && !dashed
                ? null
                : Border.all(
                    color: ring ?? Theme.of(context).colorScheme.outline,
                    width: dashed ? 1.5 : 2,
                  ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: dashed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
        if (showPresence)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CheckMark extends StatelessWidget {
  const CheckMark({super.key, required this.selected, this.size = 24});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 1.5,
        ),
      ),
      child: selected
          ? StrokeIcon(
              StrokeIconKind.check,
              size: size * 0.66,
              color: scheme.onPrimary,
              strokeWidth: 2.6,
            )
          : null,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.step, required this.onBack});

  final int step;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          icon: StrokeIcon(StrokeIconKind.chevronLeft, color: scheme.onSurface),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: step / 5,
              minHeight: 4,
              backgroundColor: scheme.outlineVariant,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text('$step of 5', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class SelectableOption extends StatelessWidget {
  const SelectableOption({
    super.key,
    required this.title,
    required this.selected,
    required this.onPressed,
    this.subtitle,
    this.minHeight = 56,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPressed;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: selected
                                    ? tokens.brandDark
                                    : scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                CheckMark(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
