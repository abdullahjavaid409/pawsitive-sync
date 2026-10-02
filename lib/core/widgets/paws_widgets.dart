import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
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
    this.borderWidth = 2,
    this.showPresence = false,
    this.dashed = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double size;
  final double fontSize;
  final Color? borderColor;
  final double borderWidth;
  final bool showPresence;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final ring = borderColor;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (dashed)
          CustomPaint(
            size: Size(size, size),
            painter: DashedCirclePainter(
              color: ring ?? Theme.of(context).colorScheme.outline,
              strokeWidth: borderWidth,
            ),
          ),
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : background,
            shape: BoxShape.circle,
            border: ring == null || dashed
                ? null
                : Border.all(color: ring, width: borderWidth),
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

class DashedCirclePainter extends CustomPainter {
  const DashedCirclePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = size.center(Offset.zero);
    const dash = 3.2;
    const gap = 3.2;
    final circumference = 2 * 3.141592653589793 * radius;
    final count = (circumference / (dash + gap)).floor();
    final sweep = (dash / circumference) * 2 * 3.141592653589793;
    final step = (dash + gap) / circumference * 2 * 3.141592653589793;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5707963267948966 + i * step,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.enterOf(context),
      curve: AppMotion.enterCurve,
      width: 51,
      height: 31,
      decoration: BoxDecoration(
        color: on ? scheme.primary : scheme.outline,
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedAlign(
        duration: AppMotion.enterOf(context),
        curve: AppMotion.enterCurve,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 27,
          height: 27,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
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
    return Material(
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? scheme.outlineVariant),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// Brand wordmark. Larger on welcome, compact in previews.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.compact = false, this.color});

  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Text(
      compact ? 'PAWSITIVESYNC' : 'PawsitiveSync',
      style: text.headlineSmall?.copyWith(
        fontSize: compact ? 13 : 26,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: compact ? 0.3 : -0.5,
        color: color ?? (compact ? scheme.onSurface : tokens.brandDark),
      ),
    );
  }
}

const onboardingScreenPadding = EdgeInsets.fromLTRB(24, 12, 24, 16);
const onboardingContentPadding = EdgeInsets.only(top: 28, bottom: 24);
const onboardingTitleGap = 12.0;
const onboardingSectionGap = 24.0;
const onboardingOptionGap = 12.0;
const onboardingFooterGap = 16.0;

/// One layout for setup: a quiet header, scrollable content and a reachable
/// action. Scaffold owns keyboard insets so they are never applied twice.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    this.header,
    required this.body,
    this.footer,
  });

  final Widget? header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            textStyle: theme.textTheme.titleLarge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: header,
                ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    header == null ? 20 : 28,
                    24,
                    24,
                  ),
                  child: body,
                ),
              ),
              if (footer != null) OnboardingFooter(child: footer!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps Android back aligned with the onboarding header back button.
class OnboardingStep extends StatelessWidget {
  const OnboardingStep({super.key, required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onBack();
      },
      child: child,
    );
  }
}

/// SafeArea and Scaffold already account for system and keyboard insets.
class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.step, required this.onBack});

  final int step;
  final VoidCallback onBack;

  static const _labels = [
    'Your pet',
    'Pet details',
    'Health',
    'Care circle',
    'Reminders',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerLowest,
                side: BorderSide(color: scheme.outlineVariant),
                minimumSize: const Size(44, 44),
              ),
              icon: StrokeIcon(
                StrokeIconKind.chevronLeft,
                size: 20,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(_labels[step - 1], style: text.titleSmall)),
            Text(
              MediaQuery.textScalerOf(context).scale(14) > 20
                  ? '$step/5'
                  : '$step of 5',
              style: text.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          label: 'Setup progress',
          value: 'Step $step of 5',
          child: Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.enterOf(context),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < step ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
    this.minHeight = 68,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPressed;
  final double minHeight;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return Semantics(
      checked: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (leading != null) ...[
                    ExcludeSemantics(child: leading!),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
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
      ),
    );
  }
}
