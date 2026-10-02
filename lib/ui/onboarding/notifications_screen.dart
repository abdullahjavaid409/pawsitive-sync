import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Explains dose reminders before the trial offer.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _choose(BuildContext context, {required bool ask}) async {
    final model = context.read<OnboardingViewModel>();
    if (!ask) {
      model.chooseReminders(false);
      await showMoment(
        context,
        name: 'reminders.off',
        message: 'Reminders stay off. You can allow them later in Settings.',
      );
      if (!context.mounted) return;
      context.go(AppRoutes.paywall);
      return;
    }
    final allowed = await DoseReminders.ask();
    if (!context.mounted) return;
    model.chooseReminders(allowed);
    if (!allowed) {
      await showMoment(
        context,
        name: 'reminders.off',
        message: 'Reminders stay off. You can allow them later in Settings.',
      );
      if (!context.mounted) return;
    }
    context.go(AppRoutes.paywall);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final name = context.watch<OnboardingViewModel>().petName.trim();
    final pet = name.isEmpty ? 'your pet' : name;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingHeader(
                step: 5,
                onBack: () => context.go(AppRoutes.caregivers),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(left: 12, top: 24),
                  children: [
                    Text(
                      'Answer reminders from your lock screen',
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: SoftEnter(
                        child: MomentArt('reminders.on', size: 140),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.neutral,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Material(
                              color: scheme.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(color: scheme.outlineVariant),
                              ),
                              child: InkWell(
                                onTap: () => context.push(AppRoutes.lock),
                                borderRadius: BorderRadius.circular(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  color: scheme.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'PAWSITIVESYNC',
                                                style: text.bodySmall?.copyWith(
                                                  letterSpacing: 0.3,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                'now',
                                                style: text.bodySmall,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "$pet's evening insulin",
                                            style: text.titleMedium,
                                          ),
                                          Text(
                                            '2 units with food · due 8:00 PM',
                                            style: text.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w400,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      child: IntrinsicHeight(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  'Mark given',
                                                  style: text.titleSmall
                                                      ?.copyWith(
                                                        color: tokens.brandDark,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            VerticalDivider(
                                              color: scheme.outlineVariant,
                                              width: 1,
                                            ),
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  'Snooze 15 min',
                                                  style: text.titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 44),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: SurfaceCard(
                                radius: 18,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sara gave $pet\'s insulin',
                                      style: text.titleSmall,
                                    ),
                                    Text(
                                      "8:02 AM · You're all set this morning",
                                      style: text.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const _Point('Mark a dose given without unlocking'),
                    const _Point('Know when someone else already gave it'),
                    const _Point('Get a refill heads-up before you run out'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: () => _choose(context, ask: true),
                      child: const Text('Turn on reminders'),
                    ),
                    TextButton(
                      onPressed: () => _choose(context, ask: false),
                      child: const Text('Not now'),
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

class _Point extends StatelessWidget {
  const _Point(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StrokeIcon(
            StrokeIconKind.check,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
