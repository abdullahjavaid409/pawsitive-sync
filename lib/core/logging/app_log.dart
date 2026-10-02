import 'dart:convert';
import 'dart:developer' as developer;

/// One structured line for the DevTools Logging view.
///
/// The message stays readable in the console. The JSON on `error` is the
/// data object DevTools opens in the details pane. Call this from a
/// repository, a navigation change, or a tap handler. Never from `build`.
abstract final class AppLog {
  static void event(String name, [Map<String, Object?> fields = const {}]) {
    developer.log(
      _line(name, fields),
      name: 'pawsitive.${name.split('.').first}',
      level: 800,
      error: _json(fields),
    );
  }

  static void error(
    String name,
    Object error,
    StackTrace? stack, [
    Map<String, Object?> fields = const {},
  ]) {
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
