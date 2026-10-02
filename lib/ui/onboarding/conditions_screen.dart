import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';

class ConditionsScreen extends StatelessWidget {
  const ConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = model.petName.trim().isEmpty
        ? 'your pet'
        : model.petName.trim();
    final count = model.conditions.length;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.petDetails),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 3,
          onBack: () => context.go(AppRoutes.petDetails),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingTitle(
              'What care does $name need?',
              'Choose all that apply. This helps us organize their care.',
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const OnboardingArtwork('health', height: 76),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Their care, in one place',
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add medicines and a schedule after setup.',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            for (final option in OnboardingViewModel.conditionOptions) ...[
              SelectableOption(
                title: option.$1,
                subtitle: option.$2,
                selected: model.conditions.contains(option.$1),
                onPressed: () => model.toggleCondition(option.$1),
              ),
              const SizedBox(height: onboardingOptionGap),
            ],
          ],
        ),
        footer: FilledButton(
          onPressed: count == 0 ? null : () => context.go(AppRoutes.caregivers),
          child: Text(
            count == 0
                ? 'Select at least one'
                : 'Continue with $count selected',
          ),
        ),
      ),
    );
  }
}
