import 'package:flutter/material.dart';

/// Window size from the space this widget was given.
///
/// Material window classes, measured in logical pixels. Layout branches on
/// width only — never on device type or orientation.
/// https://docs.flutter.dev/ui/adaptive-responsive/general
enum WindowClass { compact, medium, expanded }

/// Width breakpoints for compact, medium, and expanded windows.
abstract final class AdaptiveLayout {
  /// Bottom navigation below this width; a rail at and above it.
  static const compactBreakpoint = 600.0;

  /// Extended rail at and above this width.
  static const expandedBreakpoint = 840.0;

  /// Single-column cap so a phone layout does not span an iPad.
  static const maxPaneWidth = 600.0;

  /// Sheets stay a dialog-width column on a large window.
  static const sheetConstraints = BoxConstraints(maxWidth: 640);

  static WindowClass classify(double width) {
    if (width < compactBreakpoint) return WindowClass.compact;
    if (width < expandedBreakpoint) return WindowClass.medium;
    return WindowClass.expanded;
  }
}

/// Leaves compact layouts untouched and centers a max-width column once the
/// slot is wider than [AdaptiveLayout.maxPaneWidth].
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AdaptiveLayout.maxPaneWidth) {
          return child;
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AdaptiveLayout.maxPaneWidth,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
