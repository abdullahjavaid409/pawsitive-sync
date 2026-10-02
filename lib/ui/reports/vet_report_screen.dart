import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:provider/provider.dart';

/// Summarizes recent doses so they can be shared with a vet.
class VetReportScreen extends StatefulWidget {
  const VetReportScreen({super.key});

  @override
  State<VetReportScreen> createState() => _VetReportScreenState();
}

class _VetReportScreenState extends State<VetReportScreen> {
  int _days = 30;
  bool _showWho = true;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final pet = care.pets.first;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.pets);
                        }
                      },
                      icon: StrokeIcon(
                        StrokeIconKind.chevronLeft,
                        color: scheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Vet report',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  "Ready for ${pet.name}'s checkup",
                  style: text.headlineMedium,
                ),
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
                        for (final days in [30, 60, 90])
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
                                    _rangeLabel(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${pet.speciesLabel} · ${pet.ageYears} yrs · ${pet.conditions.join(', ')} · [VET CLINIC NAME]',
                              style: text.bodySmall?.copyWith(fontSize: 10),
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
                            const _Bar(
                              label: 'Insulin 2 u',
                              value: '59/60',
                              fraction: 0.98,
                            ),
                            const _Bar(
                              label: 'Benazepril',
                              value: '29/30',
                              fraction: 0.97,
                            ),
                            const _Bar(
                              label: 'Fluids 100 ml',
                              value: '28/30',
                              fraction: 0.93,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'WEIGHT',
                              style: text.labelSmall?.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(
                              height: 40,
                              width: double.infinity,
                              child: _MiniChart(),
                            ),
                            Text(
                              'SYMPTOM NOTES',
                              style: text.labelSmall?.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Vomited ×4 (2 this week) · Low appetite ×1',
                              style: text.bodySmall?.copyWith(
                                fontSize: 11,
                                color: scheme.onSurface,
                              ),
                            ),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          textStyle: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          AppLog.event('report.email_unavailable');
                          _toast(
                            context,
                            'Email isn’t hooked up yet. The report is still here.',
                          );
                        },
                        icon: StrokeIcon(
                          StrokeIconKind.mail,
                          size: 18,
                          color: scheme.onSurface,
                        ),
                        label: const Text('Email vet'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          textStyle: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimary,
                          ),
                        ),
                        onPressed: () {
                          AppLog.event('report.export_unavailable');
                          _toast(
                            context,
                            'Can’t save a PDF yet. You can still read it here.',
                          );
                        },
                        icon: StrokeIcon(
                          StrokeIconKind.download,
                          size: 18,
                          color: scheme.onPrimary,
                        ),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rangeLabel() {
    return switch (_days) {
      60 => 'Aug 4 – Oct 2, 2026',
      90 => 'Jul 4 – Oct 2, 2026',
      _ => 'Sep 3 – Oct 2, 2026',
    };
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

class _MiniChart extends StatelessWidget {
  const _MiniChart();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.25)
      ..lineTo(size.width * 0.17, size.height * 0.3)
      ..lineTo(size.width * 0.33, size.height * 0.35)
      ..lineTo(size.width * 0.5, size.height * 0.5)
      ..lineTo(size.width * 0.67, size.height * 0.6)
      ..lineTo(size.width * 0.83, size.height * 0.75)
      ..lineTo(size.width, size.height * 0.85);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.color != color;
}
