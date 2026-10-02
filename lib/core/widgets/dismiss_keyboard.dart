import 'package:flutter/material.dart';

/// Closes the keyboard when the user taps outside a focused field.
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  static void unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: unfocus,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
