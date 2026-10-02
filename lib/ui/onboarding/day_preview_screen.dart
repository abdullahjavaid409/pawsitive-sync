import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/story_art.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// One example of a morning, before asking about the pet.
class DayPreviewScreen extends StatelessWidget {
  const DayPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.go(AppRoutes.welcome),
                  icon: StrokeIcon(
                    StrokeIconKind.chevronLeft,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              const Center(
                child: SoftEnter(child: StoryArt('medicine', size: 132)),
              ),
              const SizedBox(height: 16),
              Text('A morning', style: text.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Sara already gave the insulin. You can see that.',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: StrokeIcon(
                        StrokeIconKind.check,
                        size: 20,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Morning insulin', style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text('Given by Sara at 8:02 AM', style: text.bodyMedium),
                        ],
                      ),
                    ),
                    InitialsAvatar(
                      label: 'S',
                      size: 28,
                      background: tokens.brandSoft,
                      foreground: tokens.brandDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.pet),
                child: const Text('Get started'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  context.read<OnboardingViewModel>().finish(reminders: false);
                  context.go(AppRoutes.household);
                },
                child: const Text('I was invited to a household'),
              ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
