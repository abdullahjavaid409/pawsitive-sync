import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

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

/// A form field that inherits the app’s input tokens while keeping the common
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
      contextMenuBuilder: appContextMenuBuilder,
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
      // v14: round, ink when on, a soft ink ring when off.
      decoration: BoxDecoration(
        color: selected ? scheme.onSurface : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? scheme.onSurface
              : scheme.onSurface.withValues(alpha: 0.25),
          width: 2,
        ),
      ),
      child: selected
          ? StrokeIcon(
              StrokeIconKind.check,
              size: size * 0.6,
              color: tokens.surfaces.card,
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
    final shape = BorderRadius.circular(radius);
    // Depth comes from a soft shadow, not a hairline; a caller that needs an
    // outline (a selected or warning card) still passes [borderColor].
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: PawsElevation.card(Theme.of(context).brightness),
      ),
      child: Material(
        color: tokens.surfaces.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// The real app icon, masked like iOS does, for brand spots and previews of
/// system surfaces (notifications, lock screen) so they match the device.
class AppIconMark extends StatelessWidget {
  const AppIconMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: Image.asset(
          'assets/brand/app_icon.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
        ),
      ),
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
      compact ? 'GAVE IT' : 'Gave It',
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
    // v14 onboarding: the app's tile inputs, and a taller full-width pill.
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            padding: EdgeInsets.symmetric(horizontal: spacing.xl),
            textStyle: theme.textTheme.titleMedium,
            shape: const StadiumBorder(),
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
      // Same side gutter as the body, so the button lines up with it.
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

/// v14 step header: a round back button, ink progress segments, and an
/// optional "Skip" on the right.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.step,
    required this.onBack,
    this.onSkip,
  });

  final int step;
  final VoidCallback onBack;

  /// Shown as "Skip" for optional steps; null hides it.
  final VoidCallback? onSkip;

  /// v14 setup has four steps after the welcome.
  static const _labels = [
    'Your pet',
    'First medicine',
    'Household',
    'Notifications',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;
    final spacing = tokens.spacing;
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: PawsElevation.card(Theme.of(context).brightness),
          ),
          child: IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: tokens.surfaces.card,
              minimumSize: const Size.square(44),
            ),
            icon: StrokeIcon(
              StrokeIconKind.chevronLeft,
              size: 20,
              color: scheme.onSurface,
            ),
          ),
        ),
        SizedBox(width: spacing.md),
        Expanded(
          child: Semantics(
            label: 'Setup progress, ${_labels[step - 1]}',
            value: 'Step $step of ${_labels.length}',
            child: Row(
              children: [
                for (var i = 0; i < _labels.length; i++) ...[
                  if (i > 0) SizedBox(width: spacing.xs),
                  Expanded(
                    child: AnimatedContainer(
                      duration: AppMotion.enterOf(context),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i < step
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(width: spacing.md),
        SizedBox(
          width: 52,
          child: onSkip == null
              ? null
              : TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    // Text on the page's right edge, like the content below.
                    alignment: AlignmentDirectional.centerEnd,
                    textStyle: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Skip'),
                ),
        ),
      ],
    );
  }
}

/// v14 ChoiceChips: equal pills in a row, ink when selected, cream with a
/// soft shadow otherwise. Wraps two per row at large text.
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  /// Read as the group's name ("Species").
  final String label;
  final List<T> options;
  final T? value;
  final String Function(T option) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    Widget pill(T option) {
      final selected = option == value;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        label: labelOf(option),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(option),
          child: AnimatedContainer(
            duration: tokens.motion.micro,
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? scheme.onSurface : tokens.surfaces.card,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected
                  ? null
                  : PawsElevation.card(Theme.of(context).brightness),
            ),
            // One line: a long label shrinks a little rather than wrap
            // mid-word in a narrow pill.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                labelOf(option),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected ? scheme.surface : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final perRow = big && options.length > 2 ? 2 : options.length;
    return Semantics(
      label: label,
      container: true,
      child: Column(
        children: [
          for (var start = 0; start < options.length; start += perRow) ...[
            if (start > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var i = start; i < start + perRow; i++) ...[
                  if (i > start) const SizedBox(width: 8),
                  Expanded(
                    child: i < options.length
                        ? pill(options[i])
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// v14 field label: 13 pt muted, inset to line up with the field's text.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
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
    // v14 option: a cream card lifted by shadow; selected gets an ink ring.
    return Semantics(
      checked: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: tokens.radii.optionShape,
          boxShadow: PawsElevation.card(Theme.of(context).brightness),
        ),
        child: Material(
          color: tokens.surfaces.card,
          shape: RoundedRectangleBorder(
            borderRadius: tokens.radii.optionShape,
            side: selected
                ? BorderSide(color: scheme.onSurface, width: 1.5)
                : BorderSide.none,
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
                                  ?.copyWith(color: scheme.onSurfaceVariant),
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
      ),
    );
  }
}
