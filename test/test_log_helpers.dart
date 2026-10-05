import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Asserts [name] was logged at least once, optionally with matching fields.
void expectLogged(String name, {Map<String, Object?>? fields, int count = 1}) {
  expect(AppLog.logCount(name), greaterThanOrEqualTo(count), reason: name);
  if (fields == null) return;
  expect(
    AppLog.testRecords.any(
      (r) =>
          r.name == name &&
          fields.entries.every((e) => r.fields[e.key] == e.value),
    ),
    isTrue,
    reason: '$name with $fields',
  );
}

void expectNotLogged(String name) {
  expect(AppLog.logged(name), isFalse, reason: 'should not log $name');
}
