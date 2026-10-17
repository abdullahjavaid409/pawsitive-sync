import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pro_lock.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/vet_report_pdf.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:share_plus/share_plus.dart';

class VetReportScreen extends StatefulWidget {
  const VetReportScreen({super.key});
  @override
  State<VetReportScreen> createState() => _VetReportScreenState();
}

class _VetReportScreenState extends State<VetReportScreen> {
  /// v14 shows a fixed four weeks (the grid's size) for everyone; Free
  /// history is 30 days, so this never needs a lock.
  static const _days = 28;

  /// The shared PDF reaches further back for Pro (the "history" gate).
  static const _proExportDays = 90;
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
    // Only built when shown; three newest in-range logs per medicine.
    final recent = <String, List<ReportEntry>>{};
    if (hasReport && _showWho) {
      for (final entry in report.recent) {
        final list = recent.putIfAbsent(entry.medicationId, () => []);
        if (list.length < 3) list.add(entry);
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: carePagePaddingOf(context),
          children: [
            // v14 header: serif "Reports" with a pet segmented control.
            _ReportsHeader(
              pets: care.pets,
              selectedId: pet?.id,
              onSelected: (id) {
                AppLog.event('report.pet_filter', {'petId': id});
                setState(() => _petId = id);
              },
            ),
            const SizedBox(height: 8),
            if (!hasReport)
              CareEmptyState(
                photo: 'assets/photos/empty-reports.jpg',
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
              _AdherenceCard(pet: pet!, report: report, days: _days),
              const SizedBox(height: 12),
              const SizedBox(height: 24),
              const CareSectionHeader('By medicine'),
              const SizedBox(height: 10),
              SurfaceCard(
                child: Column(
                  children: [
                    for (final (index, line) in report.lines.indexed)
                      _MedicineLine(
                        line: line,
                        divider: index < report.lines.length - 1,
                      ),
                  ],
                ),
              ),
              if (pet.weightKg > 0 || pet.weights.isNotEmpty) ...[
                const SizedBox(height: 24),
                _WeightCard(pet: pet),
              ],
              const SizedBox(height: 28),
              const CareSectionHeader('Care notes'),
              const SizedBox(height: 14),
              SurfaceCard(
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
                child: SwitchListTile(
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
                // Same rows as Household's activity: a tinted status dot,
                // what happened, and when.
                SurfaceCard(
                  child: Column(
                    children: [
                      for (final (i, (line, log)) in [
                        for (final line in report.lines)
                          for (final log
                              in recent[line.medication.id] ??
                                  const <ReportEntry>[])
                            (line, log),
                      ].indexed)
                        _RecentDose(
                          name: line.medication.historyName,
                          detail: [
                            '${care.dayLabel(log.day)} · ${log.timeLabel}',
                            log.who,
                            if (log.outcome != LogOutcome.given)
                              _outcomeLabel(log.outcome),
                          ].join(' · '),
                          outcome: log.outcome,
                          divider: i > 0,
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
                          context.push(
                            AppRoutes.paywallWith(
                              reason: 'vet_export',
                              from: 'report_share',
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: StrokeIcon(
                    StrokeIconKind.share,
                    size: 19,
                    color: scheme.onPrimary,
                  ),
                  label: WithProLock(
                    locked: !care.canShareVetReport,
                    onDark: true,
                    child: Text(
                      _sharing ? 'Preparing report…' : 'Share report with vet',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                care.canShareVetReport
                    ? 'A PDF of the last $_proExportDays days your vet can read, sent through the app you choose.'
                    : 'Pro makes a PDF of the last $_proExportDays days your vet can read, with who gave each dose.',
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
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final days = care.isPro ? _proExportDays : _days;
    // Pro's export covers more history than the screen; Free gets what
    // it sees.
    if (days != _days) report = care.reportFor(pet.id, days);
    final showWho = _showWho;
    final summary = _plainReport(care, pet, report);
    try {
      final watch = Stopwatch()..start();
      final pdf = await buildVetReportPdfInBackground(
        pet: pet,
        report: report,
        showCaregivers: showWho,
        generatedAt: care.now,
      );
      AppLog.event('report.pdf_built', {
        'ms': watch.elapsedMilliseconds,
        'pages': pdf.pages,
        'bytes': pdf.bytes.length,
        'days': days,
      });
      final name = vetReportFileName(pet, care.now);
      final result = await SharePlus.instance.share(
        ShareParams(
          subject: '${pet.name} · care report',
          text: summary,
          files: [
            XFile.fromData(pdf.bytes, mimeType: 'application/pdf', name: name),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: origin,
        ),
      );
      AppLog.event('report.shared', {
        'format': 'pdf',
        'days': days,
        'status': result.status.name,
      });
    } catch (error, stack) {
      AppLog.error('report.share_failed', error, stack, {'days': days});
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

  static String _outcomeLabel(LogOutcome outcome) => switch (outcome) {
    LogOutcome.given => 'Given',
    LogOutcome.skipped => 'Skipped',
    LogOutcome.uncertain => 'Not sure',
  };

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
        '• ${line.medication.historyName}${line.medication.amount.isEmpty ? '' : ' ${line.medication.amount}'} (${line.medication.whenLabel.toLowerCase()}): ${line.given} of ${line.expected}',
      if (report.skipped > 0) 'Skipped on purpose: ${report.skipped}',
      if (report.uncertain > 0) 'Not sure if given: ${report.uncertain}',
      if (report.missed > 0) 'Missed (no log): ${report.missed}',
      '',
      'Symptom notes: ${report.notes.isEmpty ? 'none logged' : [for (final e in report.notes.entries) '${e.key} ×${e.value}'].join(', ')}',
      if (_showWho) ...[
        '',
        'Recent doses:',
        for (final log in report.recent.take(10))
          '• ${log.medicationName} · ${care.dayLabel(log.day)} · ${log.timeLabel} · ${log.who}'
              '${log.outcome == LogOutcome.given ? '' : ' · ${_outcomeLabel(log.outcome)}'}',
      ],
      '',
      'Sent from Pawsitive',
    ];
    return lines.join('\n');
  }
}

/// "Reports" and, with two or more pets, a pill segmented control of names.
/// v14 weight card: latest weight, change since the first weigh-in, and a
/// line of every weigh-in. One weigh-in shows just the number.
class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.pet});

  final Pet pet;

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

  String _kg(double kg) =>
      kg.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final weights = pet.weights;
    final latest = weights.isEmpty ? pet.weightKg : weights.last.kg;
    String? change;
    if (weights.length >= 2) {
      final delta = weights.last.kg - weights.first.kg;
      final first = DateTime.tryParse(weights.first.day);
      final since = first == null ? '' : ' since ${_months[first.month - 1]}';
      change = delta.abs() < 0.05
          ? 'Steady$since'
          : '${delta > 0 ? 'Up' : 'Down'} ${_kg(delta.abs())} kg$since';
    }
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Weight', style: text.labelLarge)),
              if (change != null)
                Text(
                  change,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: _kg(latest)),
                TextSpan(
                  text: ' kg',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            style: text.headlineSmall?.copyWith(
              fontFamily: PawsTypeStyle.numberFamily,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (weights.length >= 2) ...[
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Weight over time, from ${_kg(weights.first.kg)} to '
                  '${_kg(weights.last.kg)} kilograms',
              excludeSemantics: true,
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WeightPainter(
                    values: [for (final w in weights) w.kg],
                    line: scheme.onSurface,
                    dot: context.paws.surfaces.card,
                    axis: context.paws.divider,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final w in [weights.first, weights.last])
                    Text(
                      () {
                        final d = DateTime.tryParse(w.day);
                        return d == null
                            ? w.day
                            : '${_months[d.month - 1]} ${d.day}';
                      }(),
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Update the weight on the pet’s profile to see a trend here.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.values,
    required this.line,
    required this.dot,
    required this.axis,
  });

  final List<double> values;
  final Color line;
  final Color dot;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final lo = values.reduce((a, b) => a < b ? a : b) - 0.1;
    final hi = values.reduce((a, b) => a > b ? a : b) + 0.1;
    Offset at(int i) => Offset(
      pad + i / (values.length - 1) * (size.width - pad * 2),
      pad + (1 - (values[i] - lo) / (hi - lo)) * (size.height - pad * 2),
    );
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = axis,
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      final last = i == values.length - 1;
      final c = at(i);
      canvas.drawCircle(c, last ? 4 : 2.5, Paint()..color = last ? line : dot);
      canvas.drawCircle(
        c,
        last ? 4 : 2.5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WeightPainter old) =>
      old.values != values || old.line != line;
}

class _RecentDose extends StatelessWidget {
  const _RecentDose({
    required this.name,
    required this.detail,
    required this.outcome,
    required this.divider,
  });

  final String name;
  final String detail;
  final LogOutcome outcome;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final (glyph, tint, ink) = switch (outcome) {
      LogOutcome.given => (
        Icons.check_rounded,
        paws.states.success.withValues(alpha: 0.1),
        paws.states.success,
      ),
      LogOutcome.uncertain => (
        Icons.question_mark_rounded,
        paws.amber.withValues(alpha: 0.3),
        paws.warning,
      ),
      LogOutcome.skipped => (
        Icons.remove_rounded,
        paws.surfaces.subtle,
        scheme.onSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: paws.divider)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(glyph, size: 15, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.labelLarge),
                Text(
                  detail,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsHeader extends StatelessWidget {
  const _ReportsHeader({
    required this.pets,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Pet> pets;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text('Reports', style: text.displaySmall),
          ),
          const SizedBox(width: 12),
          if (pets.length > 1)
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                // Many pets scroll sideways rather than squeeze.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: paws.surfaces.subtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final pet in pets)
                          Semantics(
                            selected: pet.id == selectedId,
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onSelected(pet.id),
                              child: AnimatedContainer(
                                duration: paws.motion.micro,
                                constraints: const BoxConstraints(
                                  minHeight: 36,
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: pet.id == selectedId
                                      ? paws.surfaces.card
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: pet.id == selectedId
                                      ? PawsElevation.card(
                                          Theme.of(context).brightness,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  pet.name,
                                  style: text.labelLarge?.copyWith(
                                    fontSize: 13,
                                    color: pet.id == selectedId
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Last 30 days", a big serif percentage of doses given, who logged them,
/// and a day grid (v14 adherence card).
class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({
    required this.pet,
    required this.report,
    required this.days,
  });

  final Pet pet;
  final PetReport report;
  final int days;

  /// The grid shows at most four weeks, so 90 days stays one glance.
  static const _gridDays = 28;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final expected = report.lines.fold<int>(0, (sum, l) => sum + l.expected);
    final given = report.given;
    final pct = expected == 0 ? null : (given * 100 / expected).round();
    final grid = report.days.length > _gridDays
        ? report.days.sublist(report.days.length - _gridDays)
        : report.days;
    final shownDays = report.days.length;
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const longDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    // Nothing due is an outline; a missed day is warm so it stands out,
    // except today, which isn't over yet.
    Color cell(DayTally d, {required bool today}) => d.isEmpty
        ? Colors.transparent
        : d.allGiven
        ? paws.states.success
        : d.noneGiven
        ? (today ? paws.surfaces.subtle : paws.warningBg)
        : paws.states.success.withValues(alpha: 0.25);
    String word(DayTally d) => d.isEmpty
        ? 'nothing scheduled'
        : d.allGiven
        ? 'all given'
        : d.noneGiven
        ? 'none given'
        : '${d.given} of ${d.expected} given';
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last $shownDays days',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: pct == null
                ? 'No doses scheduled yet'
                : '$pct percent of ${pet.name}’s doses given',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: pct == null ? '–' : '$pct'),
                      if (pct != null)
                        TextSpan(
                          text: '%',
                          style: TextStyle(
                            fontSize: 36,
                            letterSpacing: 0,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: text.displaySmall?.copyWith(
                    fontSize: 64,
                    height: 0.95,
                    letterSpacing: -1.28,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'of ${pet.name}’s doses given',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            given == 0
                ? 'No doses logged in this period yet'
                : 'From $given ${given == 1 ? 'dose' : 'doses'} logged by '
                      '${report.loggers} ${report.loggers == 1 ? 'person' : 'people'}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (grid.isNotEmpty) ...[
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7 && i < grid.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        weekdays[grid[i].day.weekday - 1],
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                  // Keep columns the same width when fewer than 7 days show.
                  for (var i = grid.length; i < 7; i++) ...[
                    const SizedBox(width: 6),
                    const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            for (var row = 0; row * 7 < grid.length; row++) ...[
              if (row > 0) const SizedBox(height: 6),
              Row(
                children: [
                  for (var col = 0; col < 7; col++) ...[
                    if (col > 0) const SizedBox(width: 6),
                    Expanded(
                      child: row * 7 + col < grid.length
                          ? Builder(
                              builder: (context) {
                                final d = grid[row * 7 + col];
                                final today = row * 7 + col == grid.length - 1;
                                return Semantics(
                                  label:
                                      '${longDays[d.day.weekday - 1]}, '
                                      '${months[d.day.month - 1]} ${d.day.day}'
                                      '${today ? ' (today)' : ''}: ${word(d)}',
                                  excludeSemantics: true,
                                  child: Container(
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: cell(d, today: today),
                                      borderRadius: BorderRadius.circular(6),
                                      border: today
                                          ? Border.all(
                                              color: scheme.onSurface,
                                              width: 2,
                                            )
                                          : d.isEmpty
                                          ? Border.all(color: paws.hairline)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            )
                          : const SizedBox(height: 28),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (final (color, label) in [
                    (paws.states.success, 'All given'),
                    (paws.states.success.withValues(alpha: 0.25), 'Some given'),
                    (paws.warningBg, 'Missed'),
                    (Colors.transparent, 'Nothing due'),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                            border: color == Colors.transparent
                                ? Border.all(color: paws.hairline)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: text.labelSmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Insulin   52 of 56 · 93%" over a green bar.
class _MedicineLine extends StatelessWidget {
  const _MedicineLine({required this.line, required this.divider});

  final ReportLine line;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final pct = line.expected == 0
        ? 0
        : (line.given * 100 / line.expected).round().clamp(0, 100);
    return Semantics(
      label:
          '${line.medication.historyName}: ${line.given} of ${line.expected} '
          'given, $pct percent',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: paws.divider))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(line.medication.historyName, style: text.labelLarge),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${line.given} of ${line.expected} · '),
                      TextSpan(
                        text: '$pct%',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                backgroundColor: paws.surfaces.subtle,
                color: paws.states.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
