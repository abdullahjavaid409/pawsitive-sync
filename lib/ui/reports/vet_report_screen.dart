import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:provider/provider.dart';

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
    final text = Theme.of(context).textTheme;
    final inShell = GoRouterState.of(context).uri.path == '/reports';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!inShell)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
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
            Text("Ready for ${pet.name}'s checkup", style: text.headlineMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final days in [30, 60, 90]) ...[
                  Expanded(
                    child: _RangeChip(
                      label: '$days days',
                      selected: _days == days,
                      onPressed: () => setState(() => _days = days),
                    ),
                  ),
                  if (days != 90) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${pet.name} · Care report', style: text.titleMedium),
                  Text(_rangeLabel(), style: text.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    '${pet.speciesLabel} · ${pet.ageYears} yrs · ${pet.conditions.join(', ')}',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text('DOSES GIVEN', style: text.labelSmall),
                  const SizedBox(height: 8),
                  const _AdherenceRow(
                    label: 'Insulin 2 u',
                    value: '59/60',
                    fraction: 59 / 60,
                  ),
                  const _AdherenceRow(
                    label: 'Benazepril',
                    value: '29/30',
                    fraction: 29 / 30,
                  ),
                  const _AdherenceRow(
                    label: 'Fluids 100 ml',
                    value: '28/30',
                    fraction: 28 / 30,
                  ),
                  const SizedBox(height: 16),
                  Text('WEIGHT', style: text.labelSmall),
                  const SizedBox(
                    height: 72,
                    width: double.infinity,
                    child: _MiniChart(),
                  ),
                  const SizedBox(height: 12),
                  Text('SYMPTOM NOTES', style: text.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Vomited ×4 (2 this week) · Low appetite ×1',
                    style: text.bodyLarge,
                  ),
                  if (_showWho) ...[
                    const SizedBox(height: 8),
                    Text('Includes who gave each dose.', style: text.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: SwitchListTile(
                title: const Text('Show who gave each dose'),
                value: _showWho,
                onChanged: (value) => setState(() => _showWho = value),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _toast(context, 'Email draft opened for your vet.'),
                    icon: StrokeIcon(
                      StrokeIconKind.file,
                      size: 18,
                      color: context.paws.brandDark,
                    ),
                    label: const Text('Email vet'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _toast(context, 'PDF saved to your device.'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: StrokeIcon(
                      StrokeIconKind.file,
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
      color: selected ? scheme.secondary : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.secondary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? scheme.onSecondary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdherenceRow extends StatelessWidget {
  const _AdherenceRow({
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: scheme.outlineVariant,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
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
      ..moveTo(0, size.height * 0.2)
      ..lineTo(size.width * 0.35, size.height * 0.28)
      ..lineTo(size.width * 0.7, size.height * 0.55)
      ..lineTo(size.width, size.height * 0.78);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.color != color;
}
