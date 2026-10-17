import 'package:flutter/widgets.dart';

/// Sinks its child a little while pressed and springs it back on release:
/// the touch feedback on primary actions. Off when Reduce Motion is on.
///
/// Uses a [Listener], so the child keeps its own tap handling and semantics.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  // Settles with a slight overshoot, like an iOS button spring.
  static const _release = Cubic(0.34, 1.56, 0.64, 1);

  void _set(bool down) {
    // The tap can remove this widget (a sheet opens, a card updates) before
    // the finger lifts; the pointer-up then arrives after dispose.
    if (!mounted || !widget.enabled || down == _down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !still ? 0.96 : 1,
        duration: still
            ? Duration.zero
            : Duration(milliseconds: _down ? 90 : 240),
        curve: _down ? Curves.easeOut : _release,
        child: widget.child,
      ),
    );
  }
}
