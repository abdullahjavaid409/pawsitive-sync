import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Records each navigation change without reading the route's arguments.
class AppRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.event('nav.push', {
      'to': route.settings.name ?? 'unnamed',
      'from': previousRoute?.settings.name ?? 'none',
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.event('nav.pop', {
      'from': route.settings.name ?? 'unnamed',
      'to': previousRoute?.settings.name ?? 'none',
    });
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLog.event('nav.replace', {
      'to': newRoute?.settings.name ?? 'unnamed',
      'from': oldRoute?.settings.name ?? 'none',
    });
  }
}
