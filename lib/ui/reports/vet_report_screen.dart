import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/app_art_size.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/story_art.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Summarizes recent doses so they can be shared with a vet.
class VetReportScreen extends StatefulWidget {
  const VetReportScreen({super.key});

  @override
  State<VetReportScreen> createState() => _VetReportScreenState();
}

class _VetReportScreenState extends State<VetReportScreen> {
  int _days = 30;
  bool _showWho = true;
  String? _petId;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final pet =
        (_petId == null ? null : care.tryPetById(_petId!)) ?? care.primaryPet;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final report = pet == null ? null : care.reportFor(pet.id, _days);
    if (pet == null || report == null || report.lines.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              Text('Reports', style: text.displaySmall),
              Text(
                'A summary to show your vet',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: StoryArt(
                  'medicine',
                  size: appEmptyStateArtSize(context),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No report yet',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                pet == null
                    ? 'Add a pet and their medicines. Every dose you log builds the report.'
                    : 'Add ${pet.name}’s medicines. Every dose you log builds the report.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => pet == null
                    ? context.push(AppRoutes.addPet)
                    : context.push('${AppRoutes.schedule}?pet=${pet.id}'),
                child: Text(pet == null ? 'Add a pet' : 'Add medicine'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Reports', style: text.displaySmall),
                Text(
                  'Ready for ${pet.name}’s checkup',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (care.pets.length > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final item in care.pets)
                        ChoiceChip(
                          label: Text(item.name),
                          selected: item.id == pet.id,
                          onSelected: (_) => setState(() => _petId = item.id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.neutral,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        for (final days in [7, 30, 90])
                          Expanded(
                            child: _RangeChip(
                              label: '$days days',
                              selected: _days == days,
                              onPressed: () => setState(() => _days = days),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.neutral,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${pet.name} · Care report',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _rangeLabel(report),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              [
                                pet.speciesLabel,
                                if (pet.ageYears > 0) '${pet.ageYears} yrs',
                                if (pet.weightKg > 0) '${pet.weightKg} kg',
                                ...pet.conditions,
                              ].join(' · '),
                              style: text.bodySmall?.copyWith(fontSize: 11),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'DOSES GIVEN',
                              style: text.labelSmall?.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final line in report.lines)
                              _Bar(
                                label: line.medication.amount.isEmpty
                                    ? line.medication.name
                                    : '${line.medication.name} ${line.medication.amount}',
                                value: '${line.given}/${line.expected}',
                                fraction: line.fraction,
                              ),
                            if (report.skipped > 0)
                              Text(
                                'Skipped on purpose: ${report.skipped}',
                                style: text.bodySmall?.copyWith(fontSize: 11),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              'SYMPTOM NOTES',
                              style: text.labelSmall?.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.notes.isEmpty
                                  ? 'None logged'
                                  : [
                                      for (final entry in report.notes.entries)
                                        '${entry.key} ×${entry.value}',
                                    ].join(' · '),
                              style: text.bodySmall?.copyWith(
                                fontSize: 11,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (_showWho) ...[
                              const SizedBox(height: 12),
                              Text(
                                'RECENT DOSES',
                                style: text.labelSmall?.copyWith(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              for (final line in report.lines)
                                for (final log in care
                                    .historyFor(line.medication.id)
                                    .take(3))
                                  Text(
                                    '${line.medication.name} · ${log.when} · ${log.who}',
                                    style: text.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SurfaceCard(
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.surfaceContainer),
                          ),
                        ),
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Dose log, weight, symptoms',
                                    style: text.bodyLarge,
                                  ),
                                ),
                                StrokeIcon(
                                  StrokeIconKind.check,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _showWho = !_showWho),
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Show who gave each dose',
                                    style: text.bodyLarge,
                                  ),
                                ),
                                PillSwitch(on: _showWho),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    onPressed: () async {
                      AppLog.event('report.shared', {'days': _days});
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      await SharePlus.instance.share(
                        ShareParams(
                          subject: '${pet.name} · care report',
                          text: _plainReport(care, pet, report),
                          sharePositionOrigin: box == null
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size,
                        ),
                      );
                    },
                    icon: StrokeIcon(
                      StrokeIconKind.share,
                      size: 18,
                      color: scheme.onPrimary,
                    ),
                    label: const Text('Share with vet'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sends this summary by email, message, or any app you pick.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
      'Sent from PawsitiveSync',
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
    return Material(
      color: selected ? scheme.surfaceContainerLowest : Colors.transparent,
      elevation: selected ? 1 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.fraction,
  });

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 11),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: scheme.outlineVariant,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
