import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/widgets/story_art.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Asks which conditions the pet is being treated for.
class ConditionsScreen extends StatelessWidget {
  const ConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final name = model.petName.trim().isEmpty
        ? 'your pet'
        : model.petName.trim();
    final count = model.conditions.length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingHeader(
                step: 3,
                onBack: () => context.go(AppRoutes.petDetails),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(left: 12, top: 24),
                  children: [
                    Text(
                      'What is $name being treated for?',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Pick all that apply. We'll set up a starter schedule for each.",
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: SoftEnter(
                        child: Column(
                          children: [
                            const StoryArt('conditions', size: 140),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final option
                        in OnboardingViewModel.conditionOptions) ...[
                      SelectableOption(
                        title: option.$1,
                        subtitle: option.$2,
                        selected: model.conditions.contains(option.$1),
                        minHeight: 64,
                        onPressed: () => model.toggleCondition(option.$1),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: FilledButton(
                  onPressed: count == 0
                      ? null
                      : () => context.go(AppRoutes.caregivers),
                  child: Text(
                    count == 0
                        ? 'Select at least one'
                        : 'Continue with $count selected',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
