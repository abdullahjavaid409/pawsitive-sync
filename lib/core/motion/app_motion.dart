import 'package:flutter/material.dart';

/// Short motion from the Flutter animation guidance.
///
/// Arrivals decelerate over 200 ms. Departures are a little faster.
/// The system "reduce motion" setting turns both off.
abstract final class AppMotion {
  static const enter = Duration(milliseconds: 200);
  static const exit = Duration(milliseconds: 140);
  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration enterOf(BuildContext context) =>
      reduced(context) ? Duration.zero : enter;

  static Duration exitOf(BuildContext context) =>
      reduced(context) ? Duration.zero : exit;

  static AnimationStyle sheet(BuildContext context) {
    return AnimationStyle(
      duration: enterOf(context),
      reverseDuration: exitOf(context),
      curve: enterCurve,
      reverseCurve: exitCurve,
    );
  }
}

/// Slides a block in a few pixels. No fade, so it stays cheap to paint.
///
/// The system "reduce motion" setting shows the block in place.
class SoftEnter extends StatefulWidget {
  const SoftEnter({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<SoftEnter> createState() => _SoftEnterState();
}

class _SoftEnterState extends State<SoftEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.enter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _controller, curve: AppMotion.enterCurve),
        );
    return SlideTransition(position: slide, child: widget.child);
  }
}
