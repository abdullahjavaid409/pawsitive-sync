import 'package:flutter/widgets.dart';

/// Defers [action] to the next frame.
///
/// Popping a route in the same frame as `ScaffoldMessenger.showSnackBar`
/// can leave the SnackBar’s dismiss timer stuck — it never times out and
/// blocks whatever sits at the bottom of the next screen. Call the
/// navigation through here instead of directly after `showSnackBar`.
void afterThisFrame(BuildContext context, VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) action();
  });
}
