// Portable end-to-end QA harness. Depends only on flutter_test, so it can be
// copied as-is into any Flutter project’s integration_test/support/ folder.
//
// Usage:
//   final qa = Qa(tester, hasEvent: (name, fields) => ...your log check...);
//   await qa.step('Feature works', () async { await qa.tap(find.text('Go')); });
//   qa.finish(); // fails the test once, listing every failed step
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef EventCheck = bool Function(String name, Map<String, Object?> fields);

class Qa {
  Qa(this.t, {this.hasEvent, this.eventCount});

  final WidgetTester t;
  final EventCheck? hasEvent;
  final int Function(String name)? eventCount;
  final _results = <String, String?>{};

  final _skipped = <String>[];
  String? _blockedBy;

  /// Runs one feature check. A failure is recorded, not thrown. Steps in a
  /// journey usually depend on the screen the last one left, so after a
  /// failure the rest are reported as skipped instead of as false failures.
  /// Pass [independent] for checks that do not need the previous screen.
  Future<void> step(
    String name,
    Future<void> Function() body, {
    bool independent = false,
  }) async {
    if (_blockedBy != null && !independent) {
      _skipped.add(name);
      debugPrint('[qa] SKIP  $name (blocked by: $_blockedBy)');
      return;
    }
    try {
      await body();
      _results[name] = null;
      debugPrint('[qa] PASS  $name');
    } catch (error) {
      _results[name] = '$error'.split('\n').take(6).join(' | ');
      _blockedBy ??= name;
      debugPrint('[qa] FAIL  $name -> ${_results[name]}');
    }
  }

  /// Prints the summary and fails the test if any step failed or was skipped.
  void finish() {
    final failed = _results.entries.where((e) => e.value != null).toList();
    final passed = _results.length - failed.length;
    final total = _results.length + _skipped.length;
    debugPrint(
      '[qa] SUMMARY $passed/$total passed, ${failed.length} failed, '
      '${_skipped.length} skipped',
    );
    for (final f in failed) {
      debugPrint('[qa] FAILED ${f.key}: ${f.value}');
    }
    expect(
      failed.isEmpty && _skipped.isEmpty,
      isTrue,
      reason: 'Failed: ${failed.map((f) => f.key).join(', ')}',
    );
  }

  /// Pumps frames for a while. Safe with looping animations, unlike pumpAndSettle.
  Future<void> settle([int ms = 600]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// Waits in real time, so network calls and SnackBar timers actually run.
  /// Long lists build rows lazily, so after a short wait it scrolls to look.
  Future<void> waitFor(Finder finder, {int seconds = 10}) async {
    final start = DateTime.now();
    final end = start.add(Duration(seconds: seconds));
    var scrolled = false;
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Not found after ${seconds}s: $finder');
      }
      if (!scrolled && DateTime.now().difference(start).inMilliseconds > 1500) {
        scrolled = true;
        if (await _scrollToFind(finder)) return;
      }
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Drags the visible RefreshIndicator’s list from the top, like a thumb.
  Future<void> pullToRefresh() async {
    final indicator = find.byType(RefreshIndicator);
    await waitFor(indicator);
    final list = find
        .descendant(of: indicator.last, matching: find.byType(Scrollable))
        .first;
    await t.fling(list, const Offset(0, 2000), 4000);
    await settle(800);
    await t.fling(list, const Offset(0, 500), 1500);
    await settle(1500);
  }

  Future<bool> _scrollToFind(Finder finder) async {
    final lists = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionIsReversed(w.axisDirection) == false &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .evaluate()
        .toList()
        .reversed;
    for (final list in lists) {
      for (final delta in const [300.0, -300.0]) {
        try {
          await t.scrollUntilVisible(
            finder,
            delta,
            scrollable: find.byElementPredicate((e) => e == list),
            maxScrolls: 30,
          );
          await settle(300);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<void> waitUntil(
    FutureOr<bool> Function() check, {
    int seconds = 10,
    String? what,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!await check()) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Not true after ${seconds}s: ${what ?? 'condition'}');
      }
      await t.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Scrolls the target into view, then taps it like a finger would.
  Future<void> tap(Finder finder, {int seconds = 10}) async {
    await waitFor(finder, seconds: seconds);
    final target = finder.first;
    await t.ensureVisible(target);
    await settle(300);
    await t.tap(target, warnIfMissed: false);
    await settle();
  }

  /// Replaces a field’s text and confirms it stuck. On real devices a second
  /// entry into a focused field can be ignored, so it refocuses and retries.
  Future<void> type(Finder field, String text) async {
    await waitFor(field);
    final target = field.first;
    final editable = find.descendant(
      of: target,
      matching: find.byType(EditableText),
    );
    String current() => t.widget<EditableText>(editable.first).controller.text;
    for (var attempt = 0; attempt < 3; attempt++) {
      await t.ensureVisible(target);
      await t.enterText(target, text);
      await settle(300);
      if (current() == text) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(300);
      await t.tap(target, warnIfMissed: false);
      await settle(300);
    }
    throw TestFailure('Field kept "${current()}" instead of "$text"');
  }

  /// Taps a button by its accessibility label (bottom tabs, icon buttons).
  /// On tablets the tabs are a side rail (no labelled Semantics button), so
  /// a rail destination with that text is tapped instead.
  Future<void> tapLabel(String label) {
    final rail = find.byType(NavigationRail);
    if (rail.evaluate().isNotEmpty) {
      final destination = find.descendant(of: rail, matching: find.text(label));
      if (destination.evaluate().isNotEmpty) return tap(destination);
    }
    return tap(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == label,
      ),
    );
  }

  Future<void> see(String text, {bool partial = false, int seconds = 10}) =>
      waitFor(
        partial ? find.textContaining(text) : find.text(text),
        seconds: seconds,
      );

  void absent(String text) {
    if (find.text(text).evaluate().isNotEmpty) {
      throw TestFailure('Should not be on screen: "$text"');
    }
  }

  /// Fails if the text is still visible after [seconds] (stuck SnackBars, spinners).
  Future<void> gone(String text, {int seconds = 5}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (find.text(text).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Still on screen after ${seconds}s: "$text"');
      }
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void event(String name, [Map<String, Object?> fields = const {}]) {
    if (!(hasEvent?.call(name, fields) ?? true)) {
      throw TestFailure('Missing event $name $fields');
    }
  }

  void noEvent(String name, [Map<String, Object?> fields = const {}]) {
    if (hasEvent?.call(name, fields) ?? false) {
      throw TestFailure('Unexpected event $name $fields');
    }
  }

  int count(String name) => eventCount?.call(name) ?? 0;
}
