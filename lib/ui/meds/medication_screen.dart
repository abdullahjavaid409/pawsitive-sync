import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                  icon: StrokeIcon(
                    StrokeIconKind.chevronLeft,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  'This medication is not on the schedule.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.today),
                  child: const Text('Back to today'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fraction = (medication.dosesLeft / medication.supplyTotal).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => context.pop(),
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
                  label: const Text('Today'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push(AppRoutes.schedule),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    textStyle: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(medication.name, style: text.headlineMedium),
                  Text(
                    medication.detail,
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SurfaceCard(
              radius: 18,
              borderColor: tokens.warningBorder,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        medication.isLow ? 'SUPPLY · LOW' : 'SUPPLY',
                        style: text.labelSmall?.copyWith(
                          color: medication.isLow
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
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${medication.dosesLeft}',
                        style: text.displaySmall?.copyWith(
                          fontSize: 44,
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
                      color: medication.isLow ? tokens.amber : scheme.primary,
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
                          text: medication.lastsUntil,
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
                          onPressed: () {
                            care.refill(medication.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Refilled. The box is full again.',
                                ),
                              ),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Can’t dial from here. Call the clinic on your phone.',
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          icon: StrokeIcon(
                            StrokeIconKind.phone,
                            size: 18,
                            color: scheme.onSurface,
                          ),
                          label: const Text('Call vet'),
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
                  _Pair(
                    label: 'If not logged',
                    value: medication.fallbackLabel,
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
                  Text(medication.onTimeLabel, style: text.bodyMedium),
                ],
              ),
            ),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final day in [
                        'Sat',
                        'Sun',
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              children: [
                                Container(
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: day == 'Wed'
                                        ? tokens.amber
                                        : scheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  day,
                                  style: text.bodySmall?.copyWith(
                                    fontWeight: day == 'Fri'
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: day == 'Fri'
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final log in medication.history)
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
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
