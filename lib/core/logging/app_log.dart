import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show debugPrint, debugPrintStack, kDebugMode;
import 'package:pawsitive_sync/data/analytics_service.dart';

/// One structured line: `[pawsitive.area] name key=value …`. Call this from a
/// repository, a navigation change, or a tap handler. Never from `build`.
class AppLogRecord {
  const AppLogRecord({
    required this.name,
    required this.fields,
    required this.isError,
  });

  final String name;
  final Map<String, Object?> fields;
  final bool isError;
}

abstract final class AppLog {
  static bool _captureForTests = false;
  static final List<AppLogRecord> testRecords = [];

  /// Records events in [testRecords] while tests run. DevTools logging unchanged.
  static void enableTestCapture() {
    _captureForTests = true;
    testRecords.clear();
  }

  static void disableTestCapture() {
    _captureForTests = false;
    testRecords.clear();
  }

  static bool logged(String name) =>
      testRecords.any((record) => record.name == name);

  static int logCount(String name) =>
      testRecords.where((record) => record.name == name).length;

  static void event(String name, [Map<String, Object?> fields = const {}]) {
    if (_captureForTests) {
      testRecords.add(
        AppLogRecord(
          name: name,
          fields: Map.unmodifiable(fields),
          isError: false,
        ),
      );
    }
    _print(name, fields);
    AnalyticsService.track(name);
  }

  static void error(
    String name,
    Object error,
    StackTrace? stack, [
    Map<String, Object?> fields = const {},
  ]) {
    if (_captureForTests) {
      testRecords.add(
        AppLogRecord(
          name: name,
          fields: Map.unmodifiable(fields),
          isError: true,
        ),
      );
    }
    _print(name, fields, error: error);
    if (kDebugMode && stack != null) {
      debugPrintStack(stackTrace: stack, maxFrames: 8);
    }
  }

  /// Marks one async case on the DevTools performance timeline.
  static Future<T> trace<T>(String name, Future<T> Function() body) {
    final task = developer.TimelineTask(filterKey: 'pawsitive')..start(name);
    return body().whenComplete(task.finish);
  }

  /// Exactly one console line per event, the same in a terminal
  /// (`flutter run`), the IDE debug console and DevTools → Logging (filter by
  /// `pawsitive`). developer.log is not used: the IDE shows it but a terminal
  /// does not, so pairing it with print doubled every line.
  static void _print(
    String name,
    Map<String, Object?> fields, {
    Object? error,
  }) {
    if (!kDebugMode) return;
    final channel = 'pawsitive.${name.split('.').first}';
    final tail = error == null ? '' : ' — ERROR $error';
    debugPrint('[$channel] ${_line(name, fields)}$tail');
  }

  static String _line(String name, Map<String, Object?> fields) {
    if (fields.isEmpty) return name;
    final buffer = StringBuffer(name);
    for (final entry in fields.entries) {
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    return buffer.toString();
  }
}
