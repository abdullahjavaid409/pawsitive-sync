import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:provider/provider.dart';

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
                    color: scheme.onSurface,
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

    final fraction = medication.dosesLeft / medication.supplyTotal;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: StrokeIcon(
                    StrokeIconKind.chevronLeft,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  label: const Text('Today'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push(AppRoutes.schedule),
                  child: Text(
                    'Edit',
                    style: text.titleSmall?.copyWith(color: scheme.primary),
                  ),
                ),
              ],
            ),
            Text(medication.name, style: text.displaySmall),
            Text(
              medication.detail,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
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
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${medication.dosesLeft}', style: text.displaySmall),
                  Text('doses left', style: text.bodyMedium),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0, 1),
                      minHeight: 8,
                      backgroundColor: scheme.outlineVariant,
                      color: medication.isLow ? tokens.warning : scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      text: 'Last dose ',
                      style: text.bodyMedium,
                      children: [
                        TextSpan(
                          text: medication.lastsUntil,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: ' at this pace'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: medication.isLow
                              ? () {
                                  care.refill(medication.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Supply reset to a full box.',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('I refilled it'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Call your clinic from the phone app.',
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        icon: StrokeIcon(
                          StrokeIconKind.phone,
                          size: 18,
                          color: scheme.onSurface,
                        ),
                        label: const Text('Call vet'),
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
                  Text(medication.onTimeLabel, style: text.bodySmall),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: day == 'Wed'
                              ? tokens.warningBg
                              : scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(day, style: text.bodySmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final log in medication.history)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: log.when,
                          style: text.bodyLarge,
                          children: [
                            if (log.lateNote != null)
                              TextSpan(
                                text: ' · ${log.lateNote}',
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.warning,
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
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
