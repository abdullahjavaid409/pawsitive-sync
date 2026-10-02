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
