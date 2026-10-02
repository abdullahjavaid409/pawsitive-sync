import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';

class CaregiversScreen extends StatefulWidget {
  const CaregiversScreen({super.key});

  @override
  State<CaregiversScreen> createState() => _CaregiversScreenState();
}

class _CaregiversScreenState extends State<CaregiversScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OnboardingViewModel>().ensureDefaultCaregiver();
    });
  }

  static const _descriptions = [
    'A simple routine of your own',
    'Keep the people at home in sync',
    'Make handovers feel easy',
    'Share the daily responsibilities',
  ];

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.conditions),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 4,
          onBack: () => context.go(AppRoutes.conditions),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingTitle(
              'Who helps with care?',
              'Choose everyone who gives a dose. You can invite them after setup.',
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const OnboardingArtwork('care', height: 96),
            ),
            const SizedBox(height: 20),
            for (
              var i = 0;
              i < OnboardingViewModel.caregiverOptions.length;
              i++
            ) ...[
              SelectableOption(
                title: OnboardingViewModel.caregiverOptions[i],
                subtitle: _descriptions[i],
                selected: model.caregivers.contains(
                  OnboardingViewModel.caregiverOptions[i],
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: StrokeIcon(
                    i == 0 ? StrokeIconKind.paw : StrokeIconKind.people,
                    size: 20,
                    color: context.paws.brandDark,
                  ),
                ),
                onPressed: () => model.toggleCaregiver(
                  OnboardingViewModel.caregiverOptions[i],
                ),
              ),
              if (i < OnboardingViewModel.caregiverOptions.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
        footer: FilledButton(
          onPressed: model.caregivers.isEmpty
              ? null
              : () {
                  AppLog.event('onboarding.step', {'step': 'caregivers'});
                  context.go(AppRoutes.notifications);
                },
          child: const Text('Continue'),
        ),
      ),
    );
  }
}
