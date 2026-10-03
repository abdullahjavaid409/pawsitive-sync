import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// A page body with the shared content inset and keyboard dismissal behavior.
///
/// Screens can opt out of scrolling when they already own a sliver or list.
class PawsPage extends StatelessWidget {
  const PawsPage({
    super.key,
    required this.child,
    this.padding,
    this.scrollable = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final spacing = context.paws.spacing;
    final content = Padding(
      padding:
          padding ??
          EdgeInsets.fromLTRB(
            spacing.pageHorizontal,
            spacing.pageTop,
            spacing.pageHorizontal,
            spacing.pageBottom,
          ),
      child: child,
    );
    if (!scrollable) return content;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: content,
    );
  }
}

/// A consistent bottom-sheet body for small, content-driven sheets.
class PawsSheet extends StatelessWidget {
  const PawsSheet({
    super.key,
    required this.child,
    this.padding,
    this.scrollable = true,
    this.showHandle = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final spacing = context.paws.spacing;
    final scheme = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHandle) ...[
          SizedBox(height: spacing.sm),
          Center(
            child: Container(
              width: 36,
              height: spacing.xs,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(spacing.xxs + 1),
              ),
            ),
          ),
          SizedBox(height: spacing.md),
        ],
        Padding(
          padding:
              padding ??
              EdgeInsets.fromLTRB(
                spacing.pageHorizontal,
                0,
                spacing.pageHorizontal,
                spacing.pageBottom,
              ),
          child: child,
        ),
      ],
    );
    final body = Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: scrollable
            ? SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: content,
              )
            : content,
      ),
    );
    return body;
  }
}

/// A form field that inherits the app's input tokens while keeping the common
/// [TextFormField] validation API in one place.
class PawsTextFormField extends StatelessWidget {
  const PawsTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.decoration,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.suffixText,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration? decoration;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final String? suffixText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final base = decoration ?? const InputDecoration();
    final resolvedDecoration = base.copyWith(
      labelText: labelText ?? base.labelText,
      hintText: hintText ?? base.hintText,
      helperText: helperText ?? base.helperText,
      errorText: errorText ?? base.errorText,
      suffixText: suffixText ?? base.suffixText,
    );
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      decoration: resolvedDecoration,
      onChanged: onChanged,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
    );
  }
}

/// A selectable pill for filters and compact choices.
class PawsChip extends StatelessWidget {
  const PawsChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.leading,
    this.enabled = true,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Widget? leading;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final states = tokens.states;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: semanticLabel ?? label,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? states.selected : tokens.surfaces.input,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.radii.chipShape,
          side: BorderSide(
            color: selected ? tokens.borders.focus : tokens.borders.subtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: tokens.radii.chipShape,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.controlHeights.chip),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.md,
                vertical: tokens.spacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    ExcludeSemantics(child: leading!),
                    SizedBox(width: tokens.spacing.sm),
                  ],
                  Text(
                    label,
                    style: text.titleSmall?.copyWith(
                      color: enabled
                          ? (selected
                                ? states.selectedContent
                                : scheme.onSurface)
                          : states.disabledContent,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (selected) ...[
                    SizedBox(width: tokens.spacing.xs),
                    StrokeIcon(
                      StrokeIconKind.check,
                      size: 16,
                      color: states.selectedContent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Calm inline error copy with an optional retry action.
class PawsErrorMessage extends StatelessWidget {
  const PawsErrorMessage({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final spacing = tokens.spacing;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(compact ? spacing.md : spacing.lg),
        decoration: BoxDecoration(
          color: tokens.states.errorContainer,
          borderRadius: tokens.radii.cardShape,
          border: Border.all(color: tokens.borders.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: spacing.xxs),
              child: StrokeIcon(
                StrokeIconKind.alert,
                size: 20,
                color: tokens.states.error,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                message,
                style: text.bodyMedium?.copyWith(color: tokens.states.error),
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(width: spacing.sm),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

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
    final tokens = context.paws;
    return AnimatedContainer(
      duration: AppMotion.enterOf(context),
      curve: AppMotion.enterCurve,
      width: 51,
      height: tokens.controlHeights.switchTrack,
      decoration: BoxDecoration(
        color: on ? scheme.primary : scheme.outline,
        borderRadius: BorderRadius.circular(
          tokens.controlHeights.switchTrack / 2,
        ),
      ),
      child: AnimatedAlign(
        duration: AppMotion.enterOf(context),
        curve: AppMotion.enterCurve,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: tokens.controlHeights.switchThumb,
          height: tokens.controlHeights.switchThumb,
          margin: EdgeInsets.symmetric(horizontal: tokens.spacing.xxs),
          decoration: const BoxDecoration(
            color: Colors.white,
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
    final tokens = context.paws;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        border: Border.all(
          color: selected
              ? tokens.states.selectedContent
              : tokens.borders.standard,
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
    final spacing = context.paws.spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, spacing.xl, 0, spacing.sm),
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
    this.radius = PawsRadii.cardValue,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    return Material(
      color: tokens.surfaces.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? tokens.borders.subtle),
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

const onboardingScreenPadding = EdgeInsets.fromLTRB(
  PawsSpacing.pageHorizontalValue,
  PawsSpacing.mdValue,
  PawsSpacing.pageHorizontalValue,
  PawsSpacing.lgValue,
);
const onboardingContentPadding = EdgeInsets.only(
  top: PawsSpacing.xxxlValue - PawsSpacing.xsValue,
  bottom: PawsSpacing.xxlValue,
);
const onboardingTitleGap = PawsSpacing.mdValue;
const onboardingSectionGap = PawsSpacing.xxlValue;
const onboardingOptionGap = PawsSpacing.mdValue;
const onboardingFooterGap = PawsSpacing.lgValue;

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
    final tokens = context.paws;
    final spacing = tokens.spacing;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          border: OutlineInputBorder(
            borderRadius: tokens.radii.cardShape,
            borderSide: BorderSide(color: tokens.borders.subtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: tokens.radii.cardShape,
            borderSide: BorderSide(color: tokens.borders.subtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: tokens.radii.cardShape,
            borderSide: BorderSide(color: tokens.borders.focus, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: Size(double.infinity, tokens.controlHeights.large),
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xl,
              vertical: spacing.lg,
            ),
            textStyle: theme.textTheme.titleLarge,
            shape: RoundedRectangleBorder(borderRadius: tokens.radii.chipShape),
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
                  padding: EdgeInsets.fromLTRB(
                    spacing.pageHorizontal,
                    spacing.sm,
                    spacing.pageHorizontal,
                    0,
                  ),
                  child: header,
                ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    spacing.pageHorizontal,
                    header == null ? spacing.xl : spacing.xxxl - spacing.xs,
                    spacing.pageHorizontal,
                    spacing.xxl,
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
    final spacing = context.paws.spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.pageHorizontal,
        spacing.md,
        spacing.pageHorizontal,
        spacing.lg,
      ),
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
    final tokens = context.paws;
    final spacing = tokens.spacing;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              style: IconButton.styleFrom(
                backgroundColor: tokens.surfaces.card,
                side: BorderSide(color: tokens.borders.subtle),
                minimumSize: Size.square(tokens.controlHeights.icon),
              ),
              icon: StrokeIcon(
                StrokeIconKind.chevronLeft,
                size: 20,
                color: scheme.onSurface,
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(child: Text(_labels[step - 1], style: text.titleSmall)),
            Text(
              MediaQuery.textScalerOf(context).scale(14) > 20
                  ? '$step/5'
                  : '$step of 5',
              style: text.bodyMedium,
            ),
          ],
        ),
        SizedBox(height: spacing.lg),
        Semantics(
          label: 'Setup progress',
          value: 'Step $step of 5',
          child: Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) SizedBox(width: spacing.xs + spacing.xxs),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.enterOf(context),
                    height: spacing.xs,
                    decoration: BoxDecoration(
                      color: i < step ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(spacing.xs),
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
    this.minHeight = PawsControlHeights.largeValue + PawsSpacing.mdValue,
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
    final spacing = tokens.spacing;
    return Semantics(
      checked: selected,
      child: Material(
        color: selected ? tokens.states.selected : tokens.surfaces.card,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.radii.optionShape,
          side: BorderSide(
            color: selected ? tokens.borders.focus : tokens.borders.subtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: tokens.radii.optionShape,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.lg,
                vertical: spacing.md,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    ExcludeSemantics(child: leading!),
                    SizedBox(width: spacing.md),
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
                          SizedBox(height: spacing.xxs),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: selected
                                      ? tokens.states.selectedContent
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.lg),
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
