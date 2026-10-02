import 'dart:developer' as developer;

/// Writes one structured line through `dart:developer`.
///
/// DevTools shows these under the `pawsitive` logger. Call it from
/// repositories, navigation, and error handlers, not from `build`.
abstract final class AppLog {
  static void event(String name, [Map<String, Object?> fields = const {}]) {
    developer.log(_line(name, fields), name: 'pawsitive', level: 800);
  }

  static void error(
    String name,
    Object error,
    StackTrace? stack, [
    Map<String, Object?> fields = const {},
  ]) {
    developer.log(
      _line(name, fields),
      name: 'pawsitive',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  static String _line(String name, Map<String, Object?> fields) {
    if (fields.isEmpty) return name;
    final parts = fields.entries.map((entry) => '${entry.key}=${entry.value}');
    return '$name ${parts.join(' ')}';
  }
}
