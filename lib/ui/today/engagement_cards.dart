import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/engagement.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's [EngagementState], or null where it isn't provided (most
/// widget tests build only the repository): engagement UI then hides.
EngagementState? maybeEngagement(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<EngagementState>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Thank-you, course-complete and milestone moments on Today. Each one is
/// dismissible, has an opt-out in Settings, and never mentions a miss.
class TodayMoments extends StatelessWidget {
  const TodayMoments({super.key, required this.care});

  final CareRepository care;

  @override
  Widget build(BuildContext context) {
    final engagement = maybeEngagement(context);
    if (engagement == null) return const SizedBox.shrink();
    final settings = engagement.settings;
    final thanks = settings.thanks
        ? Engagement.thanks(
            logs: care.logs,
            today: dayKey(care.now),
            myMemberId: care.memberId,
            shared: care.isConnected,
            dismissed: engagement.dismissedThanks,
            nameOf: (id) => care.memberById(id).name,
            medication: care.medicationById,
            pet: care.tryPetById,
          )
        : null;
    final courses = Engagement.courses(
      medications: care.medications,
      logs: care.logs,
      now: care.now,
      shared: care.isConnected && care.members.length > 1,
      dismissed: engagement.dismissedCourses,
      petName: (id) => care.tryPetById(id)?.name ?? 'Your pet',
    );
    final milestone = settings.careCount ? engagement.pendingMilestone : null;
    final milestoneText = milestone == null
        ? null
        : Engagement.milestoneText(
            milestone,
            care.primaryPet?.name ?? 'Your pet',
          );
    final cards = <Widget>[
      if (thanks != null)
        _MomentCard(
          key: ValueKey('thanks-${thanks.logId}'),
          icon: StrokeIconKind.people,
          title: thanks.text,
          onDismiss: () => engagement.dismissThanks(thanks.logId),
        ),
      for (final course in courses)
        _MomentCard(
          key: ValueKey('course-${course.medicationId}'),
          icon: StrokeIconKind.check,
          title: course.title,
          body: course.body,
          onDismiss: () => engagement.dismissCourse(course.medicationId),
        ),
      if (milestone != null && milestoneText != null)
        _MomentCard(
          key: ValueKey('milestone-$milestone'),
          icon: StrokeIconKind.paw,
          title: milestoneText,
          onDismiss: () => engagement.dismissMilestone(milestone),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            card,
          ],
        ],
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onDismiss,
    this.body,
  });

  final StrokeIconKind icon;
  final String title;
  final String? body;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Material(
      color: tokens.neutral,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: StrokeIcon(icon, size: 20, color: tokens.brandDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 2),
                      Text(body!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: StrokeIcon(StrokeIconKind.close, size: 16, color: tokens.stroke),
            ),
          ],
        ),
      ),
    );
  }
}

/// "12 days of every dose given" under the day's progress. Cumulative: it
/// only ever grows, so a missed day is never shown as a broken streak.
class CareDaysNote extends StatelessWidget {
  const CareDaysNote({super.key});

  /// Below this the count would feel like a scoreboard, not a moment.
  static const minDays = 3;

  @override
  Widget build(BuildContext context) {
    final engagement = maybeEngagement(context);
    if (engagement == null || !engagement.settings.careCount) {
      return const SizedBox.shrink();
    }
    final days = engagement.careDayCount;
    if (days < minDays) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Text(
        '$days days of every dose given',
        style: text.bodySmall?.copyWith(color: context.paws.brandDark),
      ),
    );
  }
}

/// Reminders are on but the OS blocks notifications: say so plainly, once
/// per two weeks at most, with a way to fix it. Never blocks logging.
class ReminderPermissionNote extends StatelessWidget {
  const ReminderPermissionNote({super.key, required this.remindersOn});

  final bool remindersOn;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReminderPermission>(
      valueListenable: DoseReminders.permission,
      builder: (context, permission, _) {
        final engagement = maybeEngagement(context);
        final care = context.read<CareRepository>();
        if (!remindersOn ||
            permission != ReminderPermission.denied ||
            (engagement?.permissionNudgeHidden(care.now) ?? false)) {
          return const SizedBox.shrink();
        }
        final tokens = context.paws;
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: tokens.warningBg,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications are off for Pawsitive in phone Settings, so reminders can’t appear. Logging still works.',
                    style: text.bodyMedium?.copyWith(color: tokens.warning),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => engagement?.hidePermissionNudge(care.now),
                        child: const Text('Not now'),
                      ),
                      TextButton(
                        onPressed: openNotificationSettings,
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// iOS opens this app's page in Settings; elsewhere it's best effort.
Future<void> openNotificationSettings() async {
  AppLog.event('reminders.open_settings');
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } on Object catch (error, stack) {
    AppLog.error('reminders.open_settings_failed', error, stack);
  }
}
