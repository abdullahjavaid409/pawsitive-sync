import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:provider/provider.dart';

/// Lock-screen preview of a due dose, with quick actions.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  String _clockNow() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _markGiven(BuildContext context, CareRepository care, Dose due) async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await care.logDose(
      doseId: due.id,
      memberId: care.you.id,
      amount: due.amount,
      timeLabel: _clockNow(),
    );
    if (!context.mounted) return;
    setState(() => _busy = false);
    if (!saved) {
      final error = care.lastError ?? '';
      AppLog.event('lock.given.failed', {'doseId': due.id, 'error': error});
      if (error.contains('already logged')) {
        await showDoubleDoseGuard(context, due);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.isEmpty ? 'Could not save this dose.' : error)),
      );
      return;
    }
    AppLog.event('lock.given', {'doseId': due.id, 'saved': true});
    await DoseReminders.scheduleNext(care);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dose logged from the lock screen.')),
    );
    context.pop();
  }

  Future<void> _snooze(BuildContext context, CareRepository care) async {
    if (_busy) return;
    setState(() => _busy = true);
    await DoseReminders.snoozeMinutes(care, 15);
    if (!context.mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder snoozed for 15 minutes.')),
    );
    context.pop();
  }

  void _defer(BuildContext context, Dose? due) {
    AppLog.event('lock.deferred', {'doseId': due?.id ?? 'none'});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Left for the person on duty.')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final care = context.watch<CareRepository>();
    final due = care.nextDue;
    final pet = due == null ? care.primaryPet : care.petById(due.petId);
    final petName = pet?.name ?? 'Your pet';
    final dueTitle = due == null
        ? 'Nothing is due right now'
        : "$petName's ${due.name.toLowerCase()} is due";
    final dueBody = due == null
        ? 'You will get a reminder here when a dose is due.'
        : [if (due.amount.isNotEmpty) due.amount, due.subtitle].join(' · ');
    final latest = care.activity.isEmpty ? null : care.activity.first;

    return Scaffold(
      backgroundColor: AppColors.lock,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Text(
                dayLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.lockDate,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                clockLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -3.7,
                  height: 1,
                ),
              ),
              const SizedBox(height: 72),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockCard,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const AppWordmark(compact: true),
                          const Spacer(),
                          Text('now', style: text.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(dueTitle, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        dueBody,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockCard,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _Action(
                      label: 'Mark given',
                      color: tokens.brandDark,
                      icon: StrokeIconKind.check,
                      iconColor: tokens.brandDark,
                      onPressed: due == null || _busy
                          ? null
                          : () => _markGiven(context, care, due),
                    ),
                    _Action(
                      label: 'Snooze 15 minutes',
                      icon: StrokeIconKind.clock,
                      iconColor: scheme.onSurfaceVariant,
                      onPressed: due == null || _busy
                          ? null
                          : () => _snooze(context, care),
                    ),
                    _Action(
                      label: 'Someone else gave it',
                      icon: StrokeIconKind.people,
                      iconColor: scheme.onSurfaceVariant,
                      divider: false,
                      onPressed: _busy ? null : () => _defer(context, due),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lockHistory,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              latest == null
                                  ? 'No doses logged yet today'
                                  : '${latest.actor} ${latest.action}',
                              style: text.titleSmall,
                            ),
                            Text(
                              latest == null
                                  ? 'Given doses show up here'
                                  : [
                                      if (latest.emphasis.isNotEmpty)
                                        latest.emphasis,
                                      latest.timeLabel,
                                    ].join(' · '),
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 134,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.lockHandle,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    this.color,
    this.divider = true,
  });

  final String label;
  final StrokeIconKind icon;
  final Color iconColor;
  final VoidCallback? onPressed;
  final Color? color;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: scheme.outlineVariant))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
                  color: color ?? scheme.onSurface,
                ),
              ),
            ),
            StrokeIcon(icon, size: 20, color: iconColor),
          ],
        ),
      ),
    );
  }
}
