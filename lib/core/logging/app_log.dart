import 'dart:convert';
import 'dart:developer' as developer;

import 'package:pawsitive_sync/data/analytics_service.dart';

/// One structured line for the DevTools Logging view.
///
/// The message stays readable in the console. The JSON on `error` is the
/// data object DevTools opens in the details pane. Call this from a
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
        AppLogRecord(name: name, fields: Map.unmodifiable(fields), isError: false),
      );
    }
    developer.log(
      _line(name, fields),
      name: 'pawsitive.${name.split('.').first}',
      level: 800,
      error: _json(fields),
    );
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
        AppLogRecord(name: name, fields: Map.unmodifiable(fields), isError: true),
      );
    }
    developer.log(
      _line(name, fields),
      name: 'pawsitive.${name.split('.').first}',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  /// Marks one async case on the DevTools performance timeline.
  static Future<T> trace<T>(String name, Future<T> Function() body) {
    final task = developer.TimelineTask(filterKey: 'pawsitive')..start(name);
    return body().whenComplete(task.finish);
  }

  static String? _json(Map<String, Object?> fields) {
    if (fields.isEmpty) return null;
    return jsonEncode(fields);
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
