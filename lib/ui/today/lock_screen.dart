import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:provider/provider.dart';

/// Quick care opened from a widget, or previewed inside the app.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.doseId, this.day});
  final String? doseId;
  final String? day;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  Future<void> _snooze(CareRepository care, Dose dose) async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await DoseReminders.snoozeMinutes(care, 15, target: dose);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'We’ll remind you again in 15 minutes.' : 'Could not set the reminder. Check notification permissions in Settings.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final staleLink = widget.day != null && widget.day != dayKey(care.now);
    final dose = staleLink
        ? null
        : widget.doseId == null
        ? care.nextDue
        : care.doseById(widget.doseId!);
    final pet = dose == null ? care.primaryPet : care.petById(dose.petId);
    final isDue = dose?.status == DoseStatus.due;
    final given = dose?.status == DoseStatus.given;
    final uncertain = isDue && dose?.givenById != null;
    final doses = care.doses;
    final total = doses.length;
    final logged = doses.where((d) => d.status == DoseStatus.given).length;
    final activity = care.activity;
    final latest = activity.isEmpty ? null : activity.first;

    return Scaffold(
      backgroundColor: const Color(0xFF173326),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick care',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Back to Today',
                      onPressed: () => context.go(AppRoutes.today),
                      icon: const StrokeIcon(
                        StrokeIconKind.close,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  dayLabel(care.now),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    clockLabel(care.now),
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 68,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -3,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Material(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            StrokeIcon(
                              StrokeIconKind.paw,
                              size: 19,
                              color: context.paws.brandDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Pawsitive', style: text.titleSmall),
                            ),
                            Text(
                              given
                                  ? 'Logged'
                                  : uncertain
                                  ? 'Check first'
                                  : isDue
                                  ? 'Due'
                                  : 'Today',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pet != null) ...[
                              PetPortrait(pet, size: 62),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dose?.name ??
                                        (widget.doseId != null
                                            ? 'This dose has changed'
                                            : 'All clear for now'),
                                    style: text.headlineSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    dose == null
                                        ? 'Open Today to see the latest care list.'
                                        : '${pet?.name ?? 'Your pet'}${dose.amount.isEmpty ? '' : ' · ${dose.amount}'}',
                                    style: text.bodyLarge?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (dose != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      given || uncertain
                                          ? dose.subtitle
                                          : 'Scheduled for ${dose.timeLabel}',
                                      style: text.bodyMedium,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (dose == null) {
                                    context.go(AppRoutes.today);
                                  } else if (given) {
                                    showDoubleDoseGuard(context, dose);
                                  } else if (isDue) {
                                    showLogDoseSheet(context, dose);
                                  } else {
                                    context.push(
                                      AppRoutes.medication(dose.medicationId),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                          ),
                          child: Text(
                            dose == null
                                ? 'Open Today'
                                : given
                                ? 'View logged dose'
                                : uncertain
                                ? 'Review dose'
                                : isDue
                                ? 'Log dose'
                                : 'View medicine',
                          ),
                        ),
                        if (isDue) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _snooze(care, dose!),
                            icon: const StrokeIcon(
                              StrokeIconKind.clock,
                              size: 18,
                            ),
                            label: Text(
                              _busy ? 'Setting reminder…' : 'Snooze 15 minutes',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => context.go(AppRoutes.household),
                            child: const Text('Check with my household'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        total == 0
                            ? 'Their routine starts with you.'
                            : '$logged of $total doses given today',
                        style: text.titleMedium?.copyWith(color: Colors.white),
                      ),
                      if (total > 0) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: logged / total,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            color: const Color(0xFFB8D8B8),
                          ),
                        ),
                      ],
                      if (latest != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          '${latest.actor} ${latest.action} ${latest.emphasis}',
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latest.timeLabel,
                          style: text.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
