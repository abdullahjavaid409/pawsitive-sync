import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';
import 'package:workmanager/workmanager.dart';

/// iOS BGAppRefreshTask identifier (listed in Info.plist
/// `BGTaskSchedulerPermittedIdentifiers`) and the Android unique work name.
const reminderRefreshTask = 'com.pawsitivesync.app.reminders-refresh';

/// Entry point of the background engine (Android WorkManager / iOS
/// BGAppRefreshTask). Must stay top-level and keep its pragma.
@pragma('vm:entry-point')
void reminderBackgroundDispatcher() {
  Workmanager().executeTask(
    (task, input) => ReminderBackground.run(task: task),
    // Android stopped the job early (quota, Doze, constraints): next run or
    // app open re-plans; the safety-net notification is already pending.
    onTaskStopped: (task, reason) async =>
        AppLog.event('reminders.background_stopped', {
          'task': task,
          'reason': reason,
        }),
  );
}

/// Keeps reminders going when the app isn't opened: the plan only covers
/// [ReminderPlanner.horizonDays] days, so a periodic background run
/// re-plans from the phone's own data. No network, no UI — it opens the
/// local database, plans and diffs pending notifications, nothing else.
///
/// Neither OS guarantees the run (iOS decides from usage; Android may defer
/// in Doze or after a force-stop), so the planner's "keep reminders going"
/// notification is the safety net.
abstract final class ReminderBackground {
  /// Android: about daily is enough (the plan reaches 7 days ahead).
  static const androidEvery = Duration(hours: 12);

  /// iOS: earliest-begin hint; iOS picks the real time.
  static const iosEarliest = Duration(hours: 6);

  /// iOS gives a refresh ~30 s; finish (or give up) well before.
  static const budget = Duration(seconds: 25);

  /// Registers the periodic job (idempotent: an existing one is kept, so
  /// launches don't reset its timer). Never throws.
  static Future<void> register() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await Workmanager().initialize(reminderBackgroundDispatcher);
      await Workmanager().registerPeriodicTask(
        reminderRefreshTask,
        reminderRefreshTask,
        frequency: androidEvery,
        initialDelay: Platform.isIOS ? iosEarliest : null,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      AppLog.event('reminders.background_registered');
    } on Object catch (error, stack) {
      // Reminders still work; they just rely on app opens + the safety net.
      AppLog.error('reminders.background_register_failed', error, stack);
    }
  }

  /// One background re-plan. [repository] is swapped in tests. Returns true
  /// when the OS should count the run as done (also for "nothing to do").
  static Future<bool> run({
    Future<CareRepository> Function()? repository,
    String task = reminderRefreshTask,
  }) async {
    final watch = Stopwatch()..start();
    DoseReminders.backgroundMode = true;
    AppLog.event('reminders.background_started', {'task': task});
    try {
      return await _run(repository ?? _load).timeout(budget);
    } on TimeoutException {
      AppLog.event('reminders.background_timeout', {
        'ms': watch.elapsedMilliseconds,
      });
      return false;
    } on Object catch (error, stack) {
      AppLog.error('reminders.background_failed', error, stack);
      return false;
    }
  }

  static Future<bool> _run(Future<CareRepository> Function() load) async {
    final watch = Stopwatch()..start();
    await ClockFormat.restore();
    final care = await load();
    if (care.pets.isEmpty || care.medications.isEmpty) {
      AppLog.event('reminders.background_skipped', {'reason': 'no_schedule'});
      return true;
    }
    await DoseReminders.reschedule(care, reason: 'background');
    AppLog.event('reminders.background_run', {
      'ms': watch.elapsedMilliseconds,
    });
    return true;
  }

  /// The household from disk. The API object only carries the saved token
  /// so copy matches the foreground ("we'll let the household know"); no
  /// request is ever made from here.
  static Future<CareRepository> _load() async {
    final api = AppConfig.hasApi
        ? HouseholdApi(Uri.parse(AppConfig.apiBaseUrl.trim()))
        : null;
    // Photo store too: reminders it adds carry the pet photo, as in the app.
    final care = CareRepository(
      api: api,
      store: HouseholdStore(),
      photoStore: PetPhotoStore(),
    );
    await care.restore();
    await care.loadRecentHistory();
    return care;
  }
}
