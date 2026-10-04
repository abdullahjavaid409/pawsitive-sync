import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:share_plus/share_plus.dart';

class VetReportScreen extends StatefulWidget {
  const VetReportScreen({super.key});
  @override
  State<VetReportScreen> createState() => _VetReportScreenState();
}

class _VetReportScreenState extends State<VetReportScreen> {
  int _days = 30;
  bool _showWho = true;
  bool _sharing = false;
  String? _petId;

  // Tab screen: rebuilds on data changes only while visible.
  @override
  Widget build(BuildContext context) => CareTabBuilder(builder: _build);

  Widget _build(BuildContext context, CareRepository care) {
    final pet = care.tryPetById(_petId ?? '') ?? care.primaryPet;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final report = pet == null ? null : care.reportFor(pet.id, _days);
    final hasReport = report != null && report.lines.isNotEmpty;
    // Only built when shown; three newest given doses per medicine.
    final recent = hasReport && _showWho
        ? {
            for (final line in report.lines)
              line.medication.id: care
                  .historyFor(line.medication.id)
                  .take(3)
                  .toList(),
          }
        : const <String, List<DoseLog>>{};

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: carePagePadding,
          children: [
            const CarePageHeader(
              title: 'Reports',
              subtitle: 'A clearer picture for their next checkup.',
            ),
            if (!care.canShareVetReport) ...[
              const SizedBox(height: 16),
              SurfaceCard(
                child: ListTile(
                  title: Text('Vet asked for a log?', style: text.titleSmall),
                  subtitle: const Text(
                    'Pro exports week-by-week reports. You can still view dose history here for free.',
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      AppLog.event('report.upgrade_tap');
                      context.push(AppRoutes.paywall);
                    },
                    child: const Text('Upgrade'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (care.pets.isNotEmpty) ...[
              CarePetPicker(
                pets: care.pets,
                selectedId: pet?.id,
                onSelected: (id) {
                  AppLog.event('report.pet_filter', {'petId': id ?? 'default'});
                  setState(() => _petId = id);
                },
              ),
              const SizedBox(height: 20),
            ],
            if (!hasReport)
              CareEmptyState(
                art: 'onboarding-health',
                title: 'Every dose tells a story.',
                description: pet == null
                    ? 'Add a pet and their medicines to start building a care record.'
                    : 'Add ${pet.name}’s medicines. Their dose history and notes will come together here.',
                action: pet == null ? 'Add a pet' : 'Add medicine',
                onAction: () => context.push(
                  pet == null
                      ? AppRoutes.addPet
                      : '${AppRoutes.schedule}?pet=${pet.id}',
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    for (final days in [7, 30, 90])
                      Expanded(
                        child: _RangeChip(
                          label: '$days days',
                          selected: _days == days,
                          onPressed: () {
                            if (_days == days) return;
                            AppLog.event('report.range', {'days': days});
                            setState(() => _days = days);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PetPortrait(pet!, size: 56),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${pet.name}’s care record',
                                style: text.headlineSmall,
                              ),
                              const SizedBox(height: 5),
                              Text(_rangeLabel(report), style: text.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Divider(color: scheme.outlineVariant),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CareMetric(
                            value:
                                '${report.lines.fold<int>(0, (sum, line) => sum + line.given)}',
                            label: 'Doses given',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CareMetric(
                            value: '${report.lines.length}',
                            label: 'Medicines',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CareMetric(
                            value: '${report.skipped}',
                            label: 'Skipped',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const CareSectionHeader('Medication record'),
              const SizedBox(height: 8),
              Text(
                'Doses logged against the schedule.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                radius: 20,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    for (final (index, line) in report.lines.indexed) ...[
                      if (index > 0) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.medication.name,
                                  style: text.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  line.medication.detail,
                                  style: text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${line.given}/${line.expected}',
                            style: text.titleSmall?.copyWith(
                              color: context.paws.brandDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Semantics(
                        label: '${line.medication.name} doses given',
                        value: '${line.given} of ${line.expected}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: line.fraction.clamp(0.0, 1.0),
                            minHeight: 7,
                            backgroundColor: scheme.primaryContainer,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const CareSectionHeader('Care notes'),
              const SizedBox(height: 14),
              SurfaceCard(
                radius: 20,
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StrokeIcon(
                      StrokeIconKind.file,
                      size: 22,
                      color: context.paws.brandDark,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        report.notes.isEmpty
                            ? 'No symptom notes in this period.'
                            : [
                                for (final entry in report.notes.entries)
                                  '${entry.key} ×${entry.value}',
                              ].join('\n'),
                        style: text.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SurfaceCard(
                radius: 20,
                child: SwitchListTile.adaptive(
                  value: _showWho,
                  onChanged: (value) {
                    AppLog.event('report.show_caregivers', {'on': value});
                    setState(() => _showWho = value);
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  title: Text('Include caregivers', style: text.titleSmall),
                  subtitle: Text(
                    'Show who logged each dose.',
                    style: text.bodyMedium,
                  ),
                ),
              ),
              if (_showWho) ...[
                const SizedBox(height: 24),
                const CareSectionHeader('Recent doses'),
                const SizedBox(height: 12),
                for (final line in report.lines)
                  for (final log in recent[line.medication.id]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StrokeIcon(
                            StrokeIconKind.check,
                            size: 18,
                            color: context.paws.brandDark,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.medication.name,
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${log.when} · ${log.who}',
                                  style: text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
              const SizedBox(height: 20),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _sharing
                      ? null
                      : care.canShareVetReport
                      ? () => _share(buttonContext, care, pet, report)
                      : () {
                          AppLog.event('report.share.blocked');
                          context.push(AppRoutes.paywall);
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: StrokeIcon(
                    StrokeIconKind.share,
                    size: 19,
                    color: scheme.onPrimary,
                  ),
                  label: Text(
                    _sharing ? 'Opening share options…' : 'Share with vet',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Share the summary through the app you choose.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _share(
    BuildContext buttonContext,
    CareRepository care,
    Pet pet,
    PetReport report,
  ) async {
    setState(() => _sharing = true);
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      AppLog.event('report.shared', {'days': _days});
      await SharePlus.instance.share(
        ShareParams(
          subject: '${pet.name} · care report',
          text: _plainReport(care, pet, report),
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error, stack) {
      AppLog.error('report.share_failed', error, stack, {'days': _days});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open sharing. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _date(DateTime day) => '${_months[day.month - 1]} ${day.day}';

  String _rangeLabel(PetReport report) =>
      '${_date(report.from)} – ${_date(report.to)}, ${report.to.year}';

  String _plainReport(CareRepository care, Pet pet, PetReport report) {
    final lines = <String>[
      '${pet.name} · care report',
      _rangeLabel(report),
      [
        pet.speciesLabel,
        if (pet.ageYears > 0) '${pet.ageYears} yrs',
        if (pet.weightKg > 0) '${pet.weightKg} kg',
        ...pet.conditions,
      ].join(' · '),
      '',
      'Doses given:',
      for (final line in report.lines)
        '• ${line.medication.name}${line.medication.amount.isEmpty ? '' : ' ${line.medication.amount}'} (${line.medication.whenLabel.toLowerCase()}): ${line.given} of ${line.expected}',
      if (report.skipped > 0) 'Skipped on purpose: ${report.skipped}',
      '',
      'Symptom notes: ${report.notes.isEmpty ? 'none logged' : [for (final e in report.notes.entries) '${e.key} ×${e.value}'].join(', ')}',
      if (_showWho) ...[
        '',
        'Recent doses:',
        for (final line in report.lines)
          for (final log in care.historyFor(line.medication.id).take(5))
            '• ${line.medication.name} · ${log.when} · ${log.who}',
      ],
      '',
      'Sent from Pawsitive',
    ];
    return lines.join('\n');
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.surfaceContainerLowest : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
