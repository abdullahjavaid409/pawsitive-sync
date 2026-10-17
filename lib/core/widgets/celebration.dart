import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';

/// A short confetti burst and a toast that rises in and leaves upward, played
/// each time [trigger] changes. Sits above the page; never blocks touches.
///
/// With Reduce Motion on, the toast simply appears and fades: no particles.
class CelebrationLayer extends StatefulWidget {
  const CelebrationLayer({
    super.key,
    required this.trigger,
    required this.message,
    this.onUndo,
  });

  /// Bump to play once.
  final ValueListenable<int> trigger;

  /// The toast's words, e.g. "Logged for everyone."
  final String message;

  /// When set, the toast offers "Undo" and stays up longer to allow it.
  final VoidCallback? onUndo;

  @override
  State<CelebrationLayer> createState() => _CelebrationLayerState();
}

class _CelebrationLayerState extends State<CelebrationLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_play);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void didUpdateWidget(CelebrationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      oldWidget.trigger.removeListener(_play);
      widget.trigger.addListener(_play);
    }
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_play);
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    // Time to read "Undo" and reach it; a plain toast leaves sooner.
    _controller.duration = Duration(
      milliseconds: widget.onUndo == null ? 2600 : 4500,
    );
    setState(() => _visible = true);
    _controller.forward(from: 0);
  }

  void _undo() {
    widget.onUndo?.call();
    _controller.stop();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final still = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      context.paws.amber,
      context.paws.states.success,
      scheme.primaryContainer,
    ];
    return IgnorePointer(
      ignoring: widget.onUndo == null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            children: [
              if (!still)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                        // The burst is the first ~35% of the timeline.
                        progress: (t / 0.35).clamp(0.0, 1.0),
                        colors: colors,
                      ),
                    ),
                  ),
                ),
              _Toast(
                progress: t,
                still: still,
                message: widget.message,
                onUndo: widget.onUndo == null ? null : _undo,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({
    required this.progress,
    required this.still,
    required this.message,
    required this.onUndo,
  });

  final double progress;
  final bool still;
  final String message;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    // Rise in over the first 12%, hold, then lift away over the last 18%.
    double opacity;
    double dy;
    if (progress < 0.12) {
      final p = Curves.easeOutCubic.transform(
        (progress / 0.12).clamp(0.0, 1.0),
      );
      opacity = p;
      dy = still ? 0 : (1 - p) * 24;
    } else if (progress > 0.82) {
      // Clamped: float rounding can land a hair past 1.0.
      final p = Curves.easeInCubic.transform(
        ((progress - 0.82) / 0.18).clamp(0.0, 1.0),
      );
      opacity = 1 - p;
      dy = still ? 0 : -p * 20;
    } else {
      opacity = 1;
      dy = 0;
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // v14 toast: an ink tile above the tab bar, check + message + Undo.
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 88,
      child: Align(
        child: Transform.translate(
          offset: Offset(0, -dy),
          child: Opacity(
            opacity: opacity,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x294A341E),
                      blurRadius: 32,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    onUndo == null ? 12 : 6,
                    onUndo == null ? 16 : 6,
                    onUndo == null ? 12 : 6,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: StrokeIcon(
                          StrokeIconKind.check,
                          size: 16,
                          color: scheme.onInverseSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: scheme.onInverseSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onUndo != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: onUndo,
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onInverseSurface,
                            minimumSize: const Size(48, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: text.labelLarge?.copyWith(fontSize: 14),
                          ),
                          child: const Text('Undo'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  static const _count = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.38);
    final eased = Curves.easeOutCubic.transform(progress);
    final paint = Paint();
    for (var i = 0; i < _count; i++) {
      // Fixed spread per piece: the same burst every time, no randomness.
      final angle = (i / _count) * math.pi * 2 + (i % 3) * 0.21;
      final distance = 110.0 + (i % 4) * 34;
      final fall = 70 * progress * progress;
      final position =
          origin +
          Offset(
            math.cos(angle) * distance * eased,
            math.sin(angle) * distance * eased - 30 * eased + fall,
          );
      paint.color = colors[i % colors.length].withValues(
        alpha: (1 - progress).clamp(0.0, 1.0),
      );
      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(angle + progress * (i.isEven ? 6 : -6));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -6, 8, 12),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
