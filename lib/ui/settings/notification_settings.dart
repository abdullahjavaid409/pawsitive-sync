import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/ui/today/engagement_cards.dart';

/// Settings → Notifications: the reminder master switch, honest permission
/// state, and one opt-out per engagement feature.
class NotificationSettings extends StatelessWidget {
  const NotificationSettings({
    super.key,
    required this.remindersOn,
    required this.onToggleReminders,
    required this.care,
  });

  /// Null while loading.
  final bool? remindersOn;
  final ValueChanged<bool> onToggleReminders;
  final CareRepository care;

  @override
  Widget build(BuildContext context) {
    final engagement = maybeEngagement(context);
    final scheme = Theme.of(context).colorScheme;
    final on = remindersOn ?? false;
    Widget divider() => Divider(height: 1, color: scheme.outlineVariant);

    Future<void> save(ReminderSettings next) async {
      await engagement!.saveSettings(next);
      await DoseReminders.reschedule(care, reason: 'settings');
    }

    final s = engagement?.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Dose reminders'),
                subtitle: const Text(
                  'A nudge when medicine is due, with Given and Snooze buttons.',
                ),
                value: on,
                onChanged: remindersOn == null ? null : onToggleReminders,
              ),
              ValueListenableBuilder<ReminderPermission>(
                valueListenable: DoseReminders.permission,
                builder: (context, permission, _) {
                  if (!on || permission != ReminderPermission.denied) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    title: Text(
                      'Blocked in phone Settings',
                      style: TextStyle(color: context.paws.warning),
                    ),
                    subtitle: const Text(
                      'Reminders can’t appear until notifications are allowed for Pawsitive. Logging still works.',
                    ),
                    trailing: TextButton(
                      onPressed: openNotificationSettings,
                      child: const Text('Open'),
                    ),
                  );
                },
              ),
              if (!kIsWeb && Platform.isAndroid)
                ValueListenableBuilder<bool>(
                  valueListenable: DoseReminders.exactAllowed,
                  builder: (context, exact, _) {
                    if (!on || exact) return const SizedBox.shrink();
                    return ListTile(
                      title: const Text('On-time reminders'),
                      subtitle: const Text(
                        'Android may deliver reminders a few minutes late. Allow alarms & reminders for exact times.',
                      ),
                      onTap: DoseReminders.requestExactAlarms,
                    );
                  },
                ),
              if (s != null) ...[
                divider(),
                SwitchListTile(
                  title: const Text('Follow-up if not logged'),
                  subtitle: const Text(
                    'One gentle nudge 30 minutes after a dose time. Never more than one.',
                  ),
                  value: on && s.followUp,
                  onChanged: on ? (v) => save(s.copyWith(followUp: v)) : null,
                ),
                divider(),
                SwitchListTile(
                  title: const Text('Weekly summary'),
                  subtitle: const Text(
                    'Sunday evening: how many doses were given this week.',
                  ),
                  value: on && s.weeklySummary,
                  onChanged: on
                      ? (v) => save(s.copyWith(weeklySummary: v))
                      : null,
                ),
                divider(),
                if (care.isPro)
                  SwitchListTile(
                    title: const Text('Refill heads-up'),
                    subtitle: const Text(
                      'One note when a tracked supply is running low.',
                    ),
                    value: on && s.refill,
                    onChanged: on ? (v) => save(s.copyWith(refill: v)) : null,
                  )
                else
                  ListTile(
                    title: const Text('Refill heads-up'),
                    subtitle: const Text('Pro · a note before a medicine runs out.'),
                    trailing: TextButton(
                      onPressed: () => context.push(
                        AppRoutes.paywallWith(from: 'settings_refill'),
                      ),
                      child: const Text('See Pro'),
                    ),
                  ),
                divider(),
                SwitchListTile(
                  title: const Text('Quiet hours'),
                  subtitle: Text(
                    '${_clock(context, s.quietStartMinute)} – ${_clock(context, s.quietEndMinute)} · '
                    'holds summaries and refill notes. Dose reminders still ring.',
                  ),
                  value: s.quietHours,
                  onChanged: (v) => save(s.copyWith(quietHours: v)),
                ),
                if (s.quietHours)
                  ListTile(
                    title: const Text('Change quiet hours'),
                    onTap: () => _pickQuietHours(context, s, save),
                  ),
              ],
            ],
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Thank-you moments'),
                  subtitle: const Text(
                    'A small note on Today when someone else gives a dose.',
                  ),
                  value: s.thanks,
                  onChanged: (v) => save(s.copyWith(thanks: v)),
                ),
                divider(),
                SwitchListTile(
                  title: const Text('Care count'),
                  subtitle: const Text(
                    'Days with every dose given. It only ever goes up.',
                  ),
                  value: s.careCount,
                  onChanged: (v) => save(s.copyWith(careCount: v)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _clock(BuildContext context, int minute) => TimeOfDay(
    hour: minute ~/ 60,
    minute: minute % 60,
  ).format(context);

  Future<void> _pickQuietHours(
    BuildContext context,
    ReminderSettings s,
    Future<void> Function(ReminderSettings) save,
  ) async {
    final start = await showTimePicker(
      context: context,
      helpText: 'Quiet hours start',
      initialTime: TimeOfDay(
        hour: s.quietStartMinute ~/ 60,
        minute: s.quietStartMinute % 60,
      ),
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: 'Quiet hours end',
      initialTime: TimeOfDay(
        hour: s.quietEndMinute ~/ 60,
        minute: s.quietEndMinute % 60,
      ),
    );
    if (end == null) return;
    await save(
      s.copyWith(
        quietStartMinute: start.hour * 60 + start.minute,
        quietEndMinute: end.hour * 60 + end.minute,
      ),
    );
  }
}
