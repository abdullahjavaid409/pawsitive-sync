import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// The Gave It signature: care written as lines in a shared logbook.
/// See docs/REDESIGN_GAVE_IT.md ("Shape").

/// Width of the time gutter left of the margin rule.
const ledgerGutter = 88.0;

/// A paper sheet with a hairline frame. Lines inside draw their own rules.
class LedgerSheet extends StatelessWidget {
  const LedgerSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaces.card,
        borderRadius: tokens.radii.cardShape,
        border: Border.all(color: tokens.borders.subtle),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One ledger line: mono time in the gutter, the margin rule, what was due,
/// and its mark on the right.
class LedgerLine extends StatelessWidget {
  const LedgerLine({
    super.key,
    required this.time,
    required this.title,
    required this.detail,
    required this.mark,
    this.last = false,
  });

  final String time;
  final String title;
  final String detail;
  final LedgerMark mark;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rule = BorderSide(color: tokens.borders.subtle);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: last ? BorderSide.none : rule),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: ledgerGutter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                child: Text(
                  time,
                  style: tokens.typography.stamp
                      .resolve(color: scheme.onSurfaceVariant)
                      .copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: tokens.borders.subtle,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: LedgerMarkBox(mark)),
            ),
          ],
        ),
      ),
    );
  }
}

/// [due] is waiting now (brand border); [later] is scheduled but not yet due.
enum LedgerMark { given, due, later, unsure }

/// The 28pt box at the end of a line: checked, empty, or dashed with "?".
class LedgerMarkBox extends StatelessWidget {
  const LedgerMarkBox(this.mark, {super.key, this.size = 28});

  final LedgerMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final states = tokens.states;
    final radius = BorderRadius.circular(PawsRadii.rowValue);
    return switch (mark) {
      LedgerMark.given => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: states.success, borderRadius: radius),
        alignment: Alignment.center,
        child: StrokeIcon(
          StrokeIconKind.check,
          size: size * 0.6,
          color: states.onSuccess,
        ),
      ),
      LedgerMark.due || LedgerMark.later => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: mark == LedgerMark.due
                ? Theme.of(context).colorScheme.primary
                : tokens.borders.standard,
            width: mark == LedgerMark.due ? 2 : 1.5,
          ),
        ),
      ),
      LedgerMark.unsure => CustomPaint(
        painter: _DashedBoxPainter(color: states.unsure),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              '?',
              style: tokens.typography.stamp.resolve(color: states.unsure),
            ),
          ),
        ),
      ),
    };
  }
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          const Radius.circular(PawsRadii.rowValue),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => old.color != color;
}

/// The rubber stamp a second caregiver sees: ALREADY GIVEN, who, when.
class GivenStamp extends StatelessWidget {
  const GivenStamp({super.key, required this.who, required this.time});

  final String who;
  final String time;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final label = tokens.typography.labelSmall.resolve(color: tokens.warning);
    return Semantics(
      label: 'Already given by $who at $time',
      excludeSemantics: true,
      child: Transform.rotate(
        angle: -3 * math.pi / 180,
        child: Container(
          // Long names truncate inside the stamp instead of widening it.
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.warningBg,
            borderRadius: BorderRadius.circular(PawsRadii.rowValue),
            border: Border.all(color: tokens.amber, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ALREADY GIVEN',
                style: label.copyWith(fontSize: 13, letterSpacing: 1.4),
              ),
              const SizedBox(height: 2),
              Text(
                '${who.toUpperCase()} · $time',
                style: tokens.typography.stamp.resolve(color: tokens.warning),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one-tap log action: a pill with a hard offset edge, pressed like a
/// stamp. The only control in the app styled this way.
class GaveItButton extends StatelessWidget {
  const GaveItButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final edge = dark ? scheme.primaryContainer : AppColors.brandPressed;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PawsRadii.standard.pill),
        boxShadow: onPressed == null
            ? null
            : [BoxShadow(color: edge, offset: const Offset(0, 3))],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
        ),
        icon: StrokeIcon(
          StrokeIconKind.check,
          size: 20,
          color: scheme.onPrimary,
        ),
        label: Text(label),
      ),
    );
  }
}

/// The day as a strip of boxes: given, due now, later. Replaces a progress
/// ring with the same marks the log uses.
class LedgerStrip extends StatelessWidget {
  const LedgerStrip({
    super.key,
    required this.given,
    required this.due,
    required this.total,
  });

  final int given;
  final int due;
  final int total;

  @override
  Widget build(BuildContext context) {
    final safeTotal = math.max(0, total);
    final safeGiven = given.clamp(0, safeTotal);
    final safeDue = due.clamp(0, safeTotal - safeGiven);
    return Semantics(
      label: 'Today’s doses',
      value: '$safeGiven of $safeTotal given',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < safeTotal; i++)
            LedgerMarkBox(
              i < safeGiven
                  ? LedgerMark.given
                  : i < safeGiven + safeDue
                  ? LedgerMark.due
                  : LedgerMark.later,
              size: 24,
            ),
        ],
      ),
    );
  }
}
