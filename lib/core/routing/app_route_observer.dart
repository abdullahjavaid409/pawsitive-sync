import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Records each navigation change without reading the route's arguments.
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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.event('nav.push', {
      'to': _name(route),
      'from': previousRoute?.settings.name ?? 'none',
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
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
