import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/post_frame.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// Shows one medication's supply, schedule, and recent doses.
class MedicationScreen extends StatelessWidget {
  const MedicationScreen({super.key, required this.medicationId});

  final String medicationId;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final medication = care.medicationById(medicationId);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    if (medication == null) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: carePagePaddingOf(context),
            children: [
              CarePageHeader(
                title: 'Medication unavailable',
                subtitle: 'This medication is not on the schedule.',
                leading: CareBackButton(fallbackRoute: AppRoutes.today),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.today),
                child: const Text('Back to today'),
              ),
            ],
          ),
        ),
      );
    }

    final showLowAlert = care.canShowLowSupplyAlerts && medication.isLow;
    final fraction = medication.supplyFraction;
    final pet = care.tryPetById(medication.petId);
    final petName = pet?.name ?? 'Pet removed';
    final history = care.historyFor(medication.id);
    final week = _week(care, medication);
    final givenThisWeek = week.fold<int>(0, (sum, day) => sum + day.given);
    final expectedThisWeek = week.fold<int>(
      0,
      (sum, day) => sum + day.expected,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.today),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    textStyle: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                    padding: const EdgeInsets.only(left: 0),
                  ),
                  icon: StrokeIcon(
                    StrokeIconKind.chevronLeft,
                    size: 22,
                    color: scheme.primary,
                  ),
                  label: const Text('Back'),
                ),
                const Spacer(),
                // Only the owner stops (archives) a medicine.
                if (care.canArchive)
                  TextButton(
                    // Logged as nav.push to=stop_medicine (the dialog).
                    onPressed: () => _confirmStop(context, care, medication),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      textStyle: text.titleMedium,
                    ),
                    child: const Text('Stop medicine'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            CarePageHeader(
              title: medication.name,
              subtitle: '$petName · ${medication.detail}',
              action: pet == null
                  ? Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: StrokeIcon(
                        StrokeIconKind.paw,
                        size: 24,
                        color: tokens.brandDark,
                      ),
                    )
                  : PetPortrait(pet, size: 56),
            ),
            const SizedBox(height: 24),
            if (!medication.tracksSupply)
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Supply tracking is off for this medicine. Your daily schedule and dose history are still saved.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              SurfaceCard(
                radius: 18,
                borderColor: showLowAlert
                    ? tokens.warningBorder
                    : scheme.outlineVariant,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          showLowAlert ? 'SUPPLY · LOW' : 'SUPPLY',
                          style: text.labelSmall?.copyWith(
                            color: showLowAlert
                                ? tokens.warning
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'of ${medication.supplyTotal}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                    if (showLowAlert) ...[
                      const SizedBox(height: 12),
                      const MomentArt(
                        'medication.low',
                        size: 72,
                        announce: false,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${medication.dosesLeft}',
                          style: text.displaySmall?.copyWith(
                            fontSize: 32,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'doses left',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        backgroundColor: tokens.neutral,
                        color: showLowAlert ? tokens.amber : scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: 'Last dose ',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                        children: [
                          TextSpan(
                            text: medication.lastsUntil(care.now),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' at this pace'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            // medication.refill.* is logged by the repository.
                            // Sitters only log doses.
                            onPressed: !care.canEditCare
                                ? null
                                : () async {
                                    final saved = await care.refill(
                                      medication.id,
                                    );
                                    if (!context.mounted) return;
                                    if (!saved) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                care.lastError ?? 'Could not save the refill. Try again.',
                                              ),
                                            ),
                                          );
                                      return;
                                    }
                                    await showMoment(
                                      context,
                                      name: 'medication.refilled',
                                      message: 'The box is full again.',
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: text.titleMedium,
                            ),
                            child: const Text('I refilled it'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SectionLabel('SCHEDULE'),
            SurfaceCard(
              child: Column(
                children: [
                  _Pair(label: 'Dose', value: medication.doseLabel),
                  _Pair(label: 'When', value: medication.whenLabel),
                  _Pair(label: 'For', value: petName),
                  _Pair(
                    label: 'Course',
                    value: medication.endDay.isEmpty
                        ? 'Ongoing'
                        : '${medication.endDay.compareTo(dayKey(care.now)) < 0 ? 'Completed' : 'Through'} ${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(medication.endDay))}',
                    divider: false,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
              child: Row(
                children: [
                  Text('LAST 7 DAYS', style: text.labelSmall),
                  const Spacer(),
                  Text(
                    expectedThisWeek == 0
                        ? 'Nothing due yet'
                        : '$givenThisWeek of $expectedThisWeek given',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final (index, day) in week.indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Semantics(
                              label: day.expected == 0
                                  ? '${day.label}: nothing due'
                                  : '${day.label}: ${day.given} of ${day.expected} given',
                              child: Column(
                                children: [
                                  Container(
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: day.expected == 0
                                          ? tokens.neutral
                                          : day.given >= day.expected
                                          ? scheme.primary
                                          : day.given > 0
                                          ? tokens.amber
                                          : scheme.surfaceContainerLowest,
                                      border: day.expected > 0 && day.given == 0
                                          ? Border.all(color: scheme.outline)
                                          : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    day.label,
                                    style: text.bodySmall?.copyWith(
                                      fontWeight: index == week.length - 1
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: index == week.length - 1
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (history.isEmpty)
                    Text(
                      'No doses logged yet. They show up here with who gave them.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  for (final log in history.take(10))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: log.when,
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w400,
                                ),
                                children: [
                                  if (log.lateNote != null)
                                    TextSpan(
                                      text: ' · ${log.lateNote}',
                                      style: TextStyle(
                                        color: tokens.warning,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Text(log.who, style: text.bodyMedium),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<({String label, int given, int expected})> _week(
    CareRepository care,
    Medication medication,
  ) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = care.now;
    final today = DateTime(now.year, now.month, now.day);

    return [
      for (var offset = 6; offset >= 0; offset--)
        () {
          final day = DateTime(today.year, today.month, today.day - offset);
          final key = dayKey(day);
          final expected = !medication.isActiveOn(key)
              ? 0
              : medication.parts
                    .where((part) => day != today || now.hour >= part.opensAt)
                    .length;
          final given = care.logs
              .where(
                (log) =>
                    log.medicationId == medication.id &&
                    log.day == key &&
                    log.outcome == LogOutcome.given,
              )
              .length;
          return (
            label: offset == 0 ? 'Today' : names[day.weekday - 1],
            given: given,
            expected: expected,
          );
        }(),
    ];
  }

  Future<void> _confirmStop(
    BuildContext context,
    CareRepository care,
    Medication medication,
  ) async {
    final stop = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'stop_medicine'),
      builder: (context) => AlertDialog(
        title: Text('Stop ${medication.name}?'),
        content: const Text(
          'It leaves Today for everyone in the household. Past doses stay in the vet report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop medicine'),
          ),
        ],
      ),
    );
    if (stop != true || !context.mounted) return;
    // medication.remove.completed is logged by the repository.
    final ok = await care.removeMedication(medication.id);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(care.lastError ?? 'Could not stop it. Try again.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${medication.name} was stopped.')));
    afterThisFrame(context, () => context.go(AppRoutes.today));
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value, this.divider = true});

  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: context.paws.divider))
            : null,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
