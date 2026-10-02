import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// First screen. The drawing and one real dose sit together, then one button.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: StrokeIcon(
                      StrokeIconKind.paw,
                      size: 18,
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('PawsitiveSync', style: text.titleLarge),
                ],
              ),
              const SizedBox(height: 20),
              const Center(
                child: SoftEnter(
                  child: MomentArt('welcome', size: 168, announce: false),
                ),
              ),
              const SizedBox(height: 16),
              SoftEnter(
                delay: const Duration(milliseconds: 80),
                child: SurfaceCard(
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Morning insulin', style: text.titleMedium),
                            Text(
                              'Given by Sara at 8:02 AM',
                              style: text.bodyMedium,
                            ),
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
              ),
              const SizedBox(height: 16),
              Text(
                'See who already gave it.',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'One shared list, so the medicine is not given twice.',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go(AppRoutes.pet),
                child: const Text('Get started'),
              ),
              Center(
                child: TextButton(
                  onPressed: () {
                    context.read<OnboardingViewModel>().finish(
                      reminders: false,
                    );
                    context.go(AppRoutes.household);
                  },
                  child: const Text('I was invited'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
