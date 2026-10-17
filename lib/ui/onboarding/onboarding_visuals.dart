import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

class OnboardingTitle extends StatelessWidget {
  const OnboardingTitle(this.title, this.description, {super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // v14 StepHeading: serif headline 34, muted 16 pt subtitle.
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineMedium),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Original SVGs share the app’s palette and remain crisp at every size.
class OnboardingArtwork extends StatelessWidget {
  const OnboardingArtwork(this.name, {super.key, required this.height});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SvgPicture.asset(
        'assets/art/onboarding-$name.svg',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}

class OnboardingNote extends StatelessWidget {
  const OnboardingNote(
    this.message, {
    super.key,
    this.icon = StrokeIconKind.check,
  });

  final String message;
  final StrokeIconKind icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StrokeIcon(icon, size: 18, color: context.paws.brandDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// v14 setup footer: the main pill, a muted hint under it while it's
/// disabled ("Add your pet's name to continue"), and an optional quiet
/// second action ("Not now").
class OnboardingCta extends StatelessWidget {
  const OnboardingCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.hintIsError = false,
    this.secondary,
    this.onSecondary,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// What's still missing, under the button. Shown whenever set, so a
  /// screen can keep Continue tappable and list every gap at once.
  final String? hint;

  /// After a tap with something missing: the hint turns to error colour.
  final bool hintIsError;
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Text(label),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hintIsError ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (secondary != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: busy ? null : onSecondary,
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            child: Text(secondary!),
          ),
        ],
      ],
    );
  }
}
