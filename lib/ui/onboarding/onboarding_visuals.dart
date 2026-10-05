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
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            height: 1.14,
            letterSpacing: -0.9,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.5,
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
