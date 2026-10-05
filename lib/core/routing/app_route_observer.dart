import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Records each navigation change without reading the route’s arguments.
class AppRouteObserver extends NavigatorObserver {
  /// go_router pages carry their path; sheets and dialogs have no name, so
  /// log what they are instead of "unnamed".
  static String _name(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return switch (route) {
      ModalBottomSheetRoute() => 'sheet',
      DialogRoute() || RawDialogRoute() => 'dialog',
      PopupRoute() => 'popup',
      PageRoute() => 'page',
      _ => route.runtimeType.toString(),
    };
  }

  /// Route name for self-closing confirmation dialogs (`showMoment`). Not
  /// navigation, so neither their push nor their pop is logged.
  static const moment = 'moment';

  /// Screens that log a richer line of their own when they open
  /// (`billing.paywall.opened` has the reason and placement).
  static const _selfLogged = {'/paywall'};

  /// The first page of a tab’s navigator. It’s part of a navigation already
  /// logged: the shell push (launch) or `nav.tab` (first visit to a tab).
  static bool _isTabRoot(Route<dynamic> route, Route<dynamic>? previous) {
    if (previous != null) return false;
    final navigator = route.navigator;
    return navigator != null &&
        navigator.context.findAncestorStateOfType<NavigatorState>() != null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name == moment || _selfLogged.contains(name)) return;
    if (_isTabRoot(route, previousRoute)) return;
    AppLog.event('nav.push', {
      'to': _name(route),
      'from': previousRoute?.settings.name ?? 'none',
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == moment) return;
    AppLog.event('nav.pop', {
      'from': _name(route),
      'to': previousRoute?.settings.name ?? 'none',
    });
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLog.event('nav.replace', {
      'to': newRoute == null ? 'none' : _name(newRoute),
      'from': oldRoute?.settings.name ?? 'none',
    });
  }
}
