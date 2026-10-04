import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Explains dose reminders before the trial offer.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _busy = false;

  Future<void> _choose(BuildContext context, {required bool ask}) async {
    if (_busy) return;
    AppLog.event('onboarding.step', {'step': 'notifications', 'ask': ask});
    setState(() => _busy = true);
    try {
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = context.watch<OnboardingViewModel>().petName.trim();
    final pet = name.isEmpty ? 'your pet' : name;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.caregivers),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 5,
          onBack: () => context.go(AppRoutes.caregivers),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingTitle(
              'Care, right on time.',
              'A gentle reminder when $pet’s medicine is due. One less thing to remember.',
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  const OnboardingArtwork('reminder', height: 80),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: 'Preview a dose reminder on the lock screen',
                    child: Material(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push(AppRoutes.lock),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: StrokeIcon(
                                      StrokeIconKind.paw,
                                      size: 14,
                                      color: scheme.onPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pawsitive',
                                      style: text.titleSmall,
                                    ),
                                  ),
                                  Text('now', style: text.bodySmall),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '$pet’s evening dose is due',
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 12),
                              Text(
                                'Preview on lock screen',
                                style: text.titleSmall?.copyWith(
                                  color: context.paws.brandDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const _Point(
              StrokeIconKind.check,
              'Log a dose from your lock screen',
            ),
            const _Point(
              StrokeIconKind.people,
              'See when someone else has given it',
            ),
            const _Point(
              StrokeIconKind.bell,
              'Get a heads-up before a refill is due',
            ),
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _choose(context, ask: true),
              child: const Text('Turn on reminders'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy ? null : () => _choose(context, ask: false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.label);

  final StrokeIconKind icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StrokeIcon(icon, size: 20, color: context.paws.brandDark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
