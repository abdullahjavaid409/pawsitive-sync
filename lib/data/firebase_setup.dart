import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/firebase_options.dart';

/// Firebase is only used for optional sign-in (Apple, Google, email), so it
/// starts after the first frame and a failure never blocks the app: logging
/// doses works with or without it.
///
/// Edge cases handled:
/// - concurrent callers share one attempt (no double init);
/// - a native-side init that already ran ("duplicate-app") counts as ready;
/// - a hung platform channel times out after [_timeout];
/// - a failure leaves [isReady] false and a later call (opening sign-in)
///   tries again instead of staying broken for the session.
abstract final class FirebaseSetup {
  static const _timeout = Duration(seconds: 10);

  static bool _ready = false;
  static Future<bool>? _running;

  /// True once [initialize] has connected this launch.
  static bool get isReady => _ready;

  /// Resolves to whether Firebase is usable. Never throws.
  static Future<bool> initialize() {
    if (_ready) return Future.value(true);
    return _running ??= _start().whenComplete(() => _running = null);
  }

  static Future<bool> _start() async {
    final watch = Stopwatch()..start();
    try {
      final FirebaseApp app;
      if (Firebase.apps.isNotEmpty) {
        app = Firebase.app();
      } else {
        app = await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(_timeout);
      }
      _ready = true;
      AppLog.event('firebase.ready', {
        'projectId': app.options.projectId,
        'signedIn': FirebaseAuth.instance.currentUser != null,
        'ms': watch.elapsedMilliseconds,
      });
    } on FirebaseException catch (error, stack) {
      if (error.code == 'duplicate-app') {
        _ready = true;
        AppLog.event('firebase.ready', {'reused': true});
      } else {
        AppLog.error('firebase.init_failed', error, stack, {
          'code': error.code,
        });
      }
    } on TimeoutException catch (error, stack) {
      AppLog.error('firebase.init_failed', error, stack, {'reason': 'timeout'});
    } on Object catch (error, stack) {
      // Unsupported platform (web, desktop) or a missing native config.
      AppLog.error('firebase.init_failed', error, stack);
    }
    return _ready;
  }
}
