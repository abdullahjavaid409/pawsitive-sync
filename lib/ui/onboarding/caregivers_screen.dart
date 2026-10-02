import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

class CaregiversScreen extends StatelessWidget {
  const CaregiversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final name = model.petName.trim().isEmpty
        ? 'your pet'
        : model.petName.trim();
    final count = model.caregiverCount;
    final label = count == 1
        ? 'Just you, one schedule'
        : '$count people, one schedule';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingHeader(
                step: 3,
                onBack: () => context.go(AppRoutes.conditions),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(left: 12, top: 24),
                  children: [
                    Text(
                      'Who else gives $name medication?',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick everyone who helps.',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    for (final option
                        in OnboardingViewModel.caregiverOptions) ...[
                      SelectableOption(
                        title: option,
                        selected: model.caregivers.contains(option),
                        onPressed: () => model.toggleCaregiver(option),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),
                    SurfaceCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InitialsAvatar(
                                label: 'You',
                                size: 28,
                                fontSize: 11,
                                background: scheme.primary,
                                foreground: scheme.onPrimary,
                                borderColor: scheme.surfaceContainerLowest,
                              ),
                              Transform.translate(
                                offset: const Offset(-8, 0),
                                child: InitialsAvatar(
                                  label: 'P',
                                  size: 28,
                                  background: tokens.brandSoft,
                                  foreground: tokens.brandDark,
                                  borderColor: scheme.surfaceContainerLowest,
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(-16, 0),
                                child: InitialsAvatar(
                                  label: 'S',
                                  size: 28,
                                  background: tokens.neutral,
                                  foreground: scheme.onSurface,
                                  borderColor: scheme.surfaceContainerLowest,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                label,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: tokens.brandDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When more than one person gives meds, doses get missed or given twice. Here, everyone sees who gave what, the moment it happens.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: FilledButton(
                  onPressed: model.caregivers.isEmpty
                      ? null
                      : () => context.go(AppRoutes.notifications),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
