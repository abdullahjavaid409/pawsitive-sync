import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                        const SizedBox(height: 48),
                        _PreviewRow(
                          filled: true,
                          title: 'Morning insulin · Miso',
                          subtitle: 'Given by Sara at 8:02 AM',
                          initials: 'S',
                          avatarBackground: tokens.brandSoft,
                          avatarForeground: tokens.brandDark,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _PreviewRow(
                            filled: false,
                            title: 'Fluids · 100 ml',
                            subtitle: 'Dan is on it · 1:00 PM',
                            initials: 'D',
                            avatarBackground: tokens.neutral,
                            avatarForeground: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.warningBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: tokens.warningBorder),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  StrokeIcon(
                                    StrokeIconKind.refresh,
                                    size: 18,
                                    color: tokens.warning,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Benazepril: 4 doses left. Refill by Tue.',
                                      style: text.bodyMedium?.copyWith(
                                        color: tokens.warning,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Every dose, seen by everyone who cares for them.',
                          style: text.displaySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'One shared schedule for your household. No missed doses, and none given twice.',
                          style: text.bodyLarge?.copyWith(
                            fontSize: 17,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        FilledButton(
                          onPressed: () => context.go(AppRoutes.pet),
                          child: const Text('Get started'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () {
                            context.read<OnboardingViewModel>().finish(
                              reminders: false,
                            );
                            context.go(AppRoutes.household);
                          },
                          child: const Text('I was invited to a household'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.filled,
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.avatarBackground,
    required this.avatarForeground,
  });

  final bool filled;
  final String title;
  final String subtitle;
  final String initials;
  final Color avatarBackground;
  final Color avatarForeground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (filled)
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
                strokeWidth: 2.2,
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline, width: 1.5),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          InitialsAvatar(
            label: initials,
            size: 28,
            background: avatarBackground,
            foreground: avatarForeground,
          ),
        ],
      ),
    );
  }
}
