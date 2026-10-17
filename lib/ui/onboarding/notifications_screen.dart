import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';

/// v14 RemindersStep: what's worth a notification, as three switches.
/// "When a dose is due" is the master switch (iOS permission); the other
/// two are the follow-up nudge and the refill heads-up (Pro) in Settings.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _busy = false;
  bool _due = true;
  bool _late = true;
  bool _supply = true;

  Future<void> _choose({required bool ask}) async {
    if (_busy) return;
    final on = ask && _due;
    AppLog.event('onboarding.step', {
      'step': 'notifications',
      'ask': on,
      'late': _late,
      'supply': _supply,
    });
    setState(() => _busy = true);
    try {
      final model = context.read<OnboardingViewModel>();
      final current = await ReminderSettingsStore.read();
      await ReminderSettingsStore.write(
        current.copyWith(followUp: _late, refill: _supply),
      );
      final allowed = on && await DoseReminders.ask();
      if (!mounted) return;
      model.chooseReminders(allowed);
      context.go(AppRoutes.ready);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<CareRepository>().isPro;
    final rows = [
      (
        'When a dose is due',
        'A quiet nudge at the scheduled time',
        _due,
        (bool v) => setState(() => _due = v),
        false,
      ),
      (
        'If a dose is late',
        'One reminder 30 minutes after, if nobody logged it',
        _due && _late,
        (bool v) => setState(() => _late = v),
        !_due,
      ),
      (
        'When supply runs low',
        isPro
            ? 'Once a tracked supply is nearly out'
            : 'Pro · turns on if you upgrade',
        // Free never gets these, so the switch isn't shown on for them.
        // The saved choice stays on, so Pro starts with it.
        isPro && _due && _supply,
        (bool v) => setState(() => _supply = v),
        !_due || !isPro,
      ),
    ];

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.caregivers),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 4,
          onBack: () => context.go(AppRoutes.caregivers),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OnboardingTitle(
              'Stay in the loop',
              'Choose what’s worth a notification. You can change this later.',
            ),
            const SizedBox(height: 28),
            SurfaceCard(
              child: Column(
                children: [
                  for (final (i, (title, detail, value, onChanged, off))
                      in rows.indexed) ...[
                    if (i > 0) Divider(height: 1, color: context.paws.hairline),
                    SwitchListTile(
                      value: value,
                      // Without due reminders the other two have nothing
                      // to follow.
                      onChanged: off ? null : onChanged,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      title: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        footer: OnboardingCta(
          label: _due ? 'Turn on notifications' : 'Continue',
          busy: _busy,
          onPressed: () => _choose(ask: true),
          secondary: _due ? 'Not now' : null,
          onSecondary: () => _choose(ask: false),
        ),
      ),
    );
  }
}
