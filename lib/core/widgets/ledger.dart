import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// The Gave It signature: care written as lines in a shared logbook.
/// See docs/REDESIGN_GAVE_IT.md ("Shape").

/// Narrowest the time gutter gets, left of the margin rule.
const ledgerGutter = 88.0;

/// The gutter never takes more than this share of the sheet. A time that
/// doesn't fit on one line wraps ("11:51" over "PM"); only a single word
/// wider than the gutter is scaled down (largest accessibility sizes).
const _maxGutterShare = 0.4;

/// Space around the time inside the gutter.
const _gutterPadding = EdgeInsetsDirectional.fromSTEB(12, 14, 8, 14);

/// The widest clock label any line can show, so the margin rule doesn't
/// move when a time goes from 9:59 to 10:00 or a new line appears.
const _widestClock = '00:00 PM';

TextStyle _gutterStyle(BuildContext context) {
  final tokens = context.paws;
  final scheme = Theme.of(context).colorScheme;
  return tokens.typography.stamp
      .resolve(color: scheme.onSurfaceVariant)
      .copyWith(fontSize: 14);
}

/// Single-line widths of [labels] as the gutter draws them, at the current
/// text size, font and direction.
Iterable<double> _gutterTextWidths(
  BuildContext context,
  Iterable<String> labels,
) sync* {
  final style = DefaultTextStyle.of(context).style.merge(_gutterStyle(context));
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  );
  try {
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      yield painter.width;
    }
  } finally {
    painter.dispose();
  }
}

/// Gutter width that fits every one of [times] on one line, capped at a
/// share of [maxWidth] when it is finite.
double ledgerGutterWidth(
  BuildContext context,
  Iterable<String> times, {
  double maxWidth = double.infinity,
}) {
  final widest = _gutterTextWidths(context, [
    _widestClock,
    ...times,
  ]).fold(0.0, math.max);
  final needed = (widest + _gutterPadding.horizontal).ceilToDouble();
  final cap = math.max(ledgerGutter, maxWidth * _maxGutterShare);
  return needed.clamp(ledgerGutter, cap);
}

/// Shares one gutter width with every [LedgerLine] in a [LedgerSheet].
class _LedgerGutter extends InheritedWidget {
  const _LedgerGutter({required this.width, required super.child});

  final double width;

  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LedgerGutter>()?.width;

  @override
  bool updateShouldNotify(_LedgerGutter oldWidget) => width != oldWidget.width;
}

/// A paper sheet with a hairline frame. Lines inside draw their own rules
/// and share a gutter wide enough for the longest time among them.
class LedgerSheet extends StatelessWidget {
  const LedgerSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final times = [
      for (final child in children)
        if (child is LedgerLine) child.time,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaces.card,
          borderRadius: tokens.radii.cardShape,
          border: Border.all(color: tokens.borders.subtle),
        ),
        child: _LedgerGutter(
          width: ledgerGutterWidth(
            context,
            times,
            maxWidth: constraints.maxWidth,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
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
    this.onPressed,
    this.semanticLabel,
    this.stamp = '',
  });

  final String time;
  final String title;
  final String detail;

  /// Who and when, set in the mono stamp face after [detail]: "YOU · 12:05
  /// AM". The ledger's answer to "did anyone give it?".
  final String stamp;
  final LedgerMark mark;
  final bool last;

  /// Makes the whole line one tap target (a dose on Today).
  final VoidCallback? onPressed;

  /// What VoiceOver reads for the line. Defaults to the time, the words and
  /// the mark ("8:00 AM, Insulin, Miso, due now").
  final String? semanticLabel;

  static String markWords(LedgerMark mark) => switch (mark) {
    LedgerMark.given => 'done',
    LedgerMark.due => 'due now',
    LedgerMark.later => 'later',
    LedgerMark.unsure => 'not sure if given',
  };

  /// The user's text size, unless one word of [time] is wider than the
  /// gutter even on a line of its own; then just enough smaller to fit.
  TextScaler _fitTime(BuildContext context, double gutter) {
    final scaler = MediaQuery.textScalerOf(context);
    final room = gutter - _gutterPadding.horizontal;
    final longestWord = _gutterTextWidths(
      context,
      time.split(' '),
    ).fold(0.0, math.max);
    if (longestWord <= room) return scaler;
    // Slightly under the exact ratio so rounding can't push it back over.
    final factor = scaler.scale(14) / 14 * (room / longestWord) * 0.98;
    return TextScaler.linear(factor);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final rule = BorderSide(color: tokens.borders.subtle);
    final gutter =
        _LedgerGutter.maybeOf(context) ??
        ledgerGutterWidth(context, [
          time,
        ], maxWidth: MediaQuery.sizeOf(context).width);
    final label =
        semanticLabel ??
        [
          time,
          title,
          detail,
          stamp,
          markWords(mark),
        ].where((part) => part.trim().isNotEmpty).join(', ');
    // The margin rule is painted over the row rather than laid out in it, so
    // the line needs no IntrinsicHeight pass (cheap in long lists).
    Widget line = Stack(
      children: [
        Row(
          children: [
            SizedBox(
              width: gutter,
              child: Padding(
                padding: _gutterPadding,
                child: Text(
                  time,
                  style: _gutterStyle(context),
                  textScaler: _fitTime(context, gutter),
                  maxLines: 2,
                  softWrap: true,
                ),
              ),
            ),
            const SizedBox(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.isNotEmpty || stamp.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: detail),
                            if (detail.isNotEmpty && stamp.isNotEmpty)
                              const TextSpan(text: '  ·  '),
                            if (stamp.isNotEmpty)
                              TextSpan(
                                text: stamp,
                                style: _gutterStyle(context)
                                    .copyWith(fontSize: 12, letterSpacing: 0.4),
                              ),
                          ],
                        ),
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: LedgerMarkBox(mark),
            ),
          ],
        ),
        PositionedDirectional(
          start: gutter,
          top: 0,
          bottom: 0,
          width: 1,
          child: ColoredBox(color: tokens.borders.subtle),
        ),
      ],
    );
    if (onPressed case final onTap?) {
      line = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: line),
      );
    }
    return Semantics(
      container: true,
      button: onPressed != null,
      label: label,
      // The InkWell's own tap is excluded with its children; give it back.
      onTap: onPressed,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: last ? BorderSide.none : rule),
        ),
        child: line,
      ),
    );
  }
}

/// The last line of a sheet: a plus in the gutter and what it adds, so
/// adding happens in the ledger itself rather than in a header action.
class LedgerAddLine extends StatelessWidget {
  const LedgerAddLine({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final gutter =
        _LedgerGutter.maybeOf(context) ??
        ledgerGutterWidth(context, const [], maxWidth: double.infinity);
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            // A full 48pt target, like every other line.
            constraints: const BoxConstraints(minHeight: 48),
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Center(
                        child: StrokeIcon(
                          StrokeIconKind.plus,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          12,
                          12,
                          12,
                        ),
                        child: Text(
                          label,
                          style: text.titleSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                PositionedDirectional(
                  start: gutter,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: tokens.borders.subtle),
                ),
              ],
            ),
          ),
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
