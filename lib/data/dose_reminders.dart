import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/push_service.dart' show PushDose;
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_platform.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

export 'package:pawsitive_sync/data/reminders/reminder_platform.dart'
    show ReminderPermission;

/// Asks the UI to open Today (and a dose's log sheet), e.g. after a
/// notification tap. [message] is shown once as a snackbar.
class ReminderOpen {
  const ReminderOpen({this.doseId, this.message});
  final String? doseId;
  final String? message;
}

/// Local dose reminders: every due dose for the next days (nearest first),
/// one optional follow-up, snooze, Given from the notification, and the
/// engagement notifications. Permission is requested only when the person
/// turns reminders on.
///
/// Everything is local: no server call is ever made from here.
abstract final class DoseReminders {
  /// Swapped in tests for a fake (no plugin there).
  @visibleForTesting
  static ReminderPlatform platform = PluginReminderPlatform();

  /// The tz database is loaded once per isolate.
  static bool _tzLoaded = false;
  static String? _zone;
  static Future<void>? _ready;
  static CareRepository? _care;
  static int? _signature;
  static Timer? _debounce;
  static Timer? _rollover;
  static Future<void>? _running;
  static bool _again = false;
  static String _againReason = '';
  static final Set<String> _logging = {};
  static final Set<int> _clearedDelivered = {};

  /// Device permission as last checked (Settings/Today show an honest
  /// inline note when reminders are on but the OS blocks them).
  static final ValueNotifier<ReminderPermission> permission = ValueNotifier(
    ReminderPermission.unknown,
  );

  /// Android only: false when exact alarms aren't allowed (reminders may
  /// then arrive a few minutes late).
  static final ValueNotifier<bool> exactAllowed = ValueNotifier(true);

  /// A pending deep link for the UI; set to null once handled.
  static final ValueNotifier<ReminderOpen?> pendingOpen = ValueNotifier(null);

  /// Doses another phone resolved (silent push) before this phone synced.
  static const _resolvedKey = 'reminders_resolved_v1';

  /// Medication id → when its refill heads-up was scheduled (epoch ms).
  static const _refillKey = 'reminders_refill_v1';

  /// Pro + shared as of the last foreground plan. A background run may not
  /// read the household token (keychain locked) and has no store login, so
  /// it reuses these instead of rewriting copy and dropping refill notes.
  static const _contextKey = 'reminders_context_v1';

  /// Native → Dart "the wall clock or zone jumped" (Android TIME_SET /
  /// TIMEZONE_CHANGED while the app runs; iOS significant time change).
  static const clockChannel = MethodChannel('pawsitive_sync/clock');

  /// True in the background-refresh isolate (no UI, no network).
  static bool backgroundMode = false;

  @visibleForTesting
  static void resetForTest() {
    _ready = null;
    _care = null;
    _signature = null;
    _debounce?.cancel();
    _rollover?.cancel();
    _running = null;
    _again = false;
    _logging.clear();
    _clearedDelivered.clear();
    _zone = null;
    backgroundMode = false;
    ClockFormat.use24h.removeListener(_onCareChanged);
    ReminderSettingsStore.changes.removeListener(_onCareChanged);
    permission.value = ReminderPermission.unknown;
    exactAllowed.value = true;
    pendingOpen.value = null;
  }

  /// Loads time zones, sets the local zone and initializes the plugin once.
  /// Concurrent callers share the same setup; a failure is retried next call.
  static Future<void> prepare() => _ready ??= _prepare();

  static Future<void> _prepare() async {
    try {
      _loadTimezones();
      await _syncZone();
      await platform.initialize(_onResponse);
      AppLog.event('reminders.ready', {'zone': _zone ?? 'unknown'});
    } catch (error, stack) {
      _ready = null;
      AppLog.error('reminders.prepare_failed', error, stack);
      rethrow;
    }
  }

  static void _loadTimezones() {
    if (_tzLoaded) return;
    tzdata.initializeTimeZones();
    _tzLoaded = true;
  }

  /// Points `tz.local` at the device zone. Returns true when it changed
  /// (travel, DST rules update, manual change) so callers reschedule.
  static Future<bool> _syncZone() async {
    _loadTimezones();
    String name;
    try {
      name = await platform.timezoneName();
    } on Object catch (error) {
      AppLog.event('reminders.timezone_unavailable', {
        'reason': '${error.runtimeType}',
      });
      name = '';
    }
    tz.Location location;
    try {
      location = tz.getLocation(name);
    } on Object {
      // Unknown id (rare aliases): a fixed offset keeps today's times right;
      // DST is then picked up on the next reschedule after the change.
      final offset = DateTime.now().timeZoneOffset;
      name = 'fixed:${offset.inMinutes}';
      location = tz.Location(name, [tz.minTime], [0], [
        tz.TimeZone(offset.inMilliseconds, isDst: false, abbreviation: 'LOCAL'),
      ]);
      AppLog.event('reminders.timezone_fallback', {
        'offsetMinutes': offset.inMinutes,
      });
    }
    final changed = _zone != null && _zone != name;
    if (changed) {
      AppLog.event('reminders.timezone_changed', {'from': _zone, 'to': name});
    }
    _zone = name;
    tz.setLocalLocation(location);
    return changed;
  }

  /// Shows the system permission dialog. Returns false when the person says no.
  static Future<bool> ask() async {
    try {
      await prepare();
      final granted = await platform.requestPermission();
      permission.value = granted
          ? ReminderPermission.granted
          : ReminderPermission.denied;
      AppLog.event('reminders.permission', {'allowed': granted});
      return granted;
    } catch (error, stack) {
      AppLog.error('reminders.permission_failed', error, stack);
      return false;
    }
  }

  /// Re-reads the OS permission (it can change in phone Settings anytime).
  static Future<ReminderPermission> refreshPermission() async {
    try {
      await prepare();
      final value = await platform.permission();
      if (value != permission.value) {
        AppLog.event('reminders.permission_state', {'state': value.name});
      }
      permission.value = value;
      exactAllowed.value = await platform.canScheduleExact();
      return value;
    } on Object catch (error, stack) {
      AppLog.error('reminders.permission_failed', error, stack);
      return permission.value;
    }
  }

  /// Android 14+: opens the exact-alarm setting. Never asked automatically.
  static Future<void> requestExactAlarms() async {
    try {
      await prepare();
      final allowed = await platform.requestExact();
      exactAllowed.value = allowed;
      AppLog.event('reminders.exact_requested', {'allowed': allowed});
      if (_care != null) reschedule(_care!, reason: 'exact_changed');
    } on Object catch (error, stack) {
      AppLog.error('reminders.exact_failed', error, stack);
    }
  }

  /// Cancels every local notification (reminders off, account deleted).
  static Future<void> cancel() async {
    try {
      await prepare();
      await platform.cancelAll();
      _signature = null;
      AppLog.event('reminders.cancelled');
    } catch (error, stack) {
      AppLog.error('reminders.cancel_failed', error, stack);
    }
  }

  /// Keeps reminders in step with [care]: any change that matters (a dose
  /// logged here or synced from another phone, a medicine or pet edited or
  /// removed) reschedules, debounced. Also re-aims at local midnight.
  static void attach(CareRepository care) {
    if (identical(_care, care)) return;
    _care?.removeListener(_onCareChanged);
    _care = care..addListener(_onCareChanged);
    // Clock format and settings change copy too; same debounced path.
    ClockFormat.use24h
      ..removeListener(_onCareChanged)
      ..addListener(_onCareChanged);
    ReminderSettingsStore.changes
      ..removeListener(_onCareChanged)
      ..addListener(_onCareChanged);
    _signature = _signatureOf(care);
    _armRollover();
  }

  /// Listens on [clockChannel]. Called once from `bootstrap` (needs the
  /// platform channels, so not from [attach], which tests call bare).
  static void listenToClock() {
    clockChannel.setMethodCallHandler((MethodCall call) async {
      final care = _care;
      final source = '${call.arguments ?? 'native'}';
      if (call.method != 'changed') {
        AppLog.event('reminders.clock_ignored', {'reason': 'unknown_method', 'method': call.method});
        return;
      }
      if (care == null) {
        // Before data loaded: launch's own reschedule uses the new clock.
        AppLog.event('reminders.clock_ignored', {'reason': 'not_attached', 'source': source});
        return;
      }
      await onClockChanged(care, source: source);
    });
  }

  /// The user moved the clock or the zone changed under a running app: the
  /// midnight timer (a monotonic duration) now aims at the wrong instant
  /// and pending reminders may be in the past. Re-arm and re-plan; the
  /// planner never schedules past instants and ids are per dose-day, so
  /// nothing doubles up.
  static Future<void> onClockChanged(
    CareRepository care, {
    String source = 'native',
  }) async {
    AppLog.event('reminders.clock_changed', {'source': source});
    _armRollover();
    care.dayChanged();
    await reschedule(care, reason: 'clock_changed');
  }

  static void _onCareChanged() {
    final care = _care;
    if (care == null) return;
    final next = _signatureOf(care);
    if (next == _signature) return;
    _signature = next;
    _debounce?.cancel();
    // A sync merges many rows in one burst: one reschedule for all of it.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      reschedule(care, reason: 'data');
    });
  }

  /// Only what changes the plan or its copy: schedules (with custom
  /// times), pets, member names ("Dan wasn't sure…"), shared mode, clock
  /// format, settings saves, recent logs, the day.
  @visibleForTesting
  static int signatureOf(CareRepository care) => _signatureOf(care);

  static int _signatureOf(CareRepository care) {
    final now = care.now;
    final since = dayKey(now.subtract(const Duration(days: 8)));
    return Object.hashAll([
      dayKey(now),
      care.isPro,
      care.isConnected,
      care.members.length,
      care.isConnected && care.members.length > 1,
      ClockFormat.use24h.value,
      ReminderSettingsStore.changes.value,
      for (final m in care.members) Object.hash(m.id, m.name, m.isYou),
      for (final m in care.medications)
        Object.hash(
          m.id,
          m.petId,
          m.name,
          m.amount,
          Object.hashAll(m.parts),
          Object.hashAll([for (final p in m.parts) m.minuteFor(p)]),
          m.startDay,
          m.endDay,
          m.dosesLeft,
        ),
      for (final p in care.pets) Object.hash(p.id, p.name, p.photoPath),
      for (final log in care.logs)
        if (log.day.compareTo(since) >= 0) Object.hash(log.id, log.outcome),
    ]);
  }

  /// Fires a reschedule (and a Today refresh) just after local midnight.
  static void _armRollover() {
    _rollover?.cancel();
    final care = _care;
    if (care == null) return;
    final now = care.now;
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _rollover = Timer(next.difference(now), () {
      AppLog.event('reminders.day_rollover');
      care.dayChanged();
      reschedule(care, reason: 'day_rollover');
      _armRollover();
    });
  }

  /// App came back: the zone, clock, permission or day may have changed.
  static Future<void> onResume(CareRepository care) async {
    _armRollover();
    await reschedule(care, reason: 'resume');
  }

  /// Brings pending notifications in line with the plan. Serialized: a
  /// call while one runs queues exactly one more run. Never throws.
  static Future<void> reschedule(
    CareRepository care, {
    String reason = 'manual',
  }) {
    if (_running != null) {
      _again = true;
      _againReason = reason;
      return _running!;
    }
    final run = _reschedule(care, reason).whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        reschedule(care, reason: _againReason);
      }
    });
    _running = run;
    return run;
  }

  static Future<void> _reschedule(CareRepository care, String reason) async {
    final watch = Stopwatch()..start();
    try {
      await prepare();
      if (await _syncZone()) reason = 'timezone_changed';
      if (!await ReminderChoice.read()) {
        await _cancelOwned();
        AppLog.event('reminders.schedule_skipped', {
          'reason': 'off',
          'trigger': reason,
        });
        return;
      }
      final allowed = await refreshPermission();
      if (allowed == ReminderPermission.denied) {
        // Nothing would show; trying again on every change is pointless.
        AppLog.event('reminders.schedule_skipped', {
          'reason': 'permission_denied',
          'trigger': reason,
        });
        return;
      }
      final settings = await ReminderSettingsStore.read();
      final snoozed = await ReminderSnooze.read();
      final resolved = await _readResolved(care);
      final refill = await _readRefill(care);
      final members = {
        for (final m in care.members) m.id: m.isYou ? 'You' : m.name,
      };
      final (:shared, :isPro) = await _context(care);
      final planned = ReminderPlanner.plan(
        ReminderPlanInput(
          now: care.now,
          location: tz.local,
          pets: care.pets,
          medications: care.medications,
          logs: care.logs,
          memberNames: members,
          settings: settings,
          shared: shared,
          isPro: isPro,
          snoozedKeys: snoozed,
          refillNotifiedAt: refill,
          resolvedKeys: resolved,
        ),
      );
      final stats = await _apply(care, planned);
      await _saveRefill(planned, refill);
      AppLog.event('reminders.scheduled', {
        'trigger': reason,
        'doses': planned.where((n) => n.kind == ReminderKind.dose).length,
        'followUps': planned.where((n) => n.kind == ReminderKind.followUp).length,
        'engagement': planned.where((n) => !n.actionable).length,
        'grouped': planned.where((n) => n.isGroup).length,
        'upkeep': planned.any((n) => n.kind == ReminderKind.upkeep),
        if (backgroundMode) 'background': true,
        'added': stats.$1,
        'cancelled': stats.$2,
        'unchanged': stats.$3,
        'exact': exactAllowed.value,
        'ms': watch.elapsedMilliseconds,
      });
    } on Object catch (error, stack) {
      AppLog.error('reminders.schedule_failed', error, stack, {
        'trigger': reason,
      });
    }
  }

  /// Shared/Pro for copy and refill notes. Foreground: from the household,
  /// saved for later. Background: the saved values (the token or store
  /// entitlement may be unreadable there), falling back to the household.
  static Future<({bool shared, bool isPro})> _context(
    CareRepository care,
  ) async {
    final live = (
      shared: care.isConnected && care.members.length > 1,
      isPro: care.isPro,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (backgroundMode) {
        final saved = prefs.getStringList(_contextKey);
        if (saved == null || saved.length < 2) return live;
        return (
          shared: saved[0] == '1' || live.shared,
          isPro: saved[1] == '1' || live.isPro,
        );
      }
      await prefs.setStringList(_contextKey, [
        live.shared ? '1' : '0',
        live.isPro ? '1' : '0',
      ]);
    } on Object catch (error, stack) {
      // Copy falls back to what this run can see.
      AppLog.error('reminders.context_failed', error, stack, {
        'background': backgroundMode,
      });
    }
    return live;
  }

  /// Diffs against what the OS has pending. Returns (added, cancelled, kept).
  static Future<(int, int, int)> _apply(
    CareRepository care,
    List<PlannedNotification> planned,
  ) async {
    final pending = {for (final p in await platform.pending()) p.id: p};
    final wanted = {for (final n in planned) n.id: n};
    final today = dayKey(care.now);
    var cancelled = 0;
    for (final p in pending.values) {
      if (wanted.containsKey(p.id)) continue;
      final kind = ReminderIds.kindOf(p.id);
      if (kind == null && p.id != ReminderIds.legacy) continue;
      if (kind == ReminderKind.snooze) {
        // A snooze the person asked for stays until the dose is resolved.
        final payload = ReminderPayload.decode(p.payload);
        if (payload != null && payload.day == today) {
          if (!payload.isGroup) {
            if (!_resolvedToday(care, payload.doseId, today)) continue;
          } else {
            // A group snooze keeps the doses still open, drops the rest.
            final done = {
              for (final key in payload.doseKeys)
                if (_resolvedToday(care, key.split('|').first, today)) key,
            };
            if (done.isEmpty) continue;
            final rest = ReminderGroups.without(payload, done, tz.local);
            AppLog.event('reminders.group_shrunk', {
              'kept': rest == null ? 0 : 1,
              'removed': rest == null ? 1 : 0,
              'from': 'snooze',
            });
            if (rest != null) {
              if (rest.id != p.id) await platform.cancel(p.id);
              await platform.schedule(rest, exact: exactAllowed.value);
              cancelled++;
              continue;
            }
          }
        }
      }
      await platform.cancel(p.id);
      cancelled++;
    }
    // Delivered (not pending) reminders for doses resolved today leave the
    // notification centre too — "Given" on one phone clears the others.
    for (final log in care.logs) {
      if (log.day != today || log.outcome == LogOutcome.uncertain) continue;
      final doseId = CareRepository.doseIdFor(log.medicationId, log.part);
      for (final kind in const [
        ReminderKind.dose,
        ReminderKind.followUp,
        ReminderKind.snooze,
      ]) {
        final id = ReminderIds.forDose(kind, doseId, today);
        if (_clearedDelivered.add(id) && !wanted.containsKey(id)) {
          await platform.cancel(id);
        }
      }
    }
    // A delivered group leaves once every dose in it is resolved. (A
    // partly resolved delivered group stays as shown: re-posting it would
    // alert again; the pending side above is always rebuilt.)
    for (final entry in _todayGroups(care, today).entries) {
      if (!entry.value.every((doseId) => _resolvedToday(care, doseId, today))) {
        continue;
      }
      for (final kind in const [
        ReminderKind.dose,
        ReminderKind.followUp,
        ReminderKind.snooze,
      ]) {
        final id = ReminderIds.of(kind, entry.key);
        if (_clearedDelivered.add(id) && !wanted.containsKey(id)) {
          await platform.cancel(id);
        }
      }
    }
    var added = 0;
    var kept = 0;
    final exact = exactAllowed.value;
    for (final n in planned) {
      if (pending[n.id]?.payload == n.payload) {
        kept++;
        continue;
      }
      await platform.schedule(n, exact: exact);
      added++;
    }
    return (added, cancelled, kept);
  }

  /// Today's group keys → their dose ids (2+ doses at one minute).
  static Map<String, List<String>> _todayGroups(CareRepository care, String today) {
    final date = DateTime.tryParse(today);
    if (date == null) return const {};
    final byKey = <String, List<String>>{};
    for (final med in care.medications) {
      if (med.isArchived || !med.isActiveOn(today)) continue;
      for (final part in med.parts) {
        final at = ReminderPlanner.at(tz.local, date, med.minuteFor(part));
        (byKey[ReminderGroups.keyFor(today, at)] ??= []).add(
          CareRepository.doseIdFor(med.id, part),
        );
      }
    }
    return {
      for (final e in byKey.entries)
        if (e.value.length > 1) e.key: e.value,
    };
  }

  static bool _resolvedToday(CareRepository care, String doseId, String day) {
    final log = care.loggedDose(doseId, day);
    return log != null && log.outcome != LogOutcome.uncertain;
  }

  static Future<void> _cancelOwned() async {
    for (final p in await platform.pending()) {
      if (ReminderIds.kindOf(p.id) != null || p.id == ReminderIds.legacy) {
        await platform.cancel(p.id);
      }
    }
  }

  /// A push said someone else gave or skipped these doses: cancel their
  /// reminder, follow-up and snooze at once (ids are derived from the dose,
  /// so this works in a background launch with nothing loaded), and keep
  /// them out of the plan until this phone syncs the log. Idempotent.
  static Future<bool> cancelForDoses(List<PushDose> doses) async {
    if (doses.isEmpty) return false;
    try {
      for (final dose in doses) {
        for (final kind in const [
          ReminderKind.dose,
          ReminderKind.followUp,
          ReminderKind.snooze,
        ]) {
          await platform.cancel(ReminderIds.forDose(kind, dose.doseId, dose.day));
        }
      }
      await _shrinkGroups({for (final d in doses) '${d.doseId}|${d.day}'});
      final prefs = await SharedPreferences.getInstance();
      final keys = {
        ...?prefs.getStringList(_resolvedKey),
        for (final dose in doses) '${dose.doseId}|${dose.day}',
      };
      await prefs.setStringList(_resolvedKey, keys.toList());
      AppLog.event('reminders.cancelled_by_push', {
        'doses': doses.length,
        'doseId': doses.first.doseId,
      });
      return true;
    } on Object catch (error, stack) {
      AppLog.error('reminders.push_cancel_failed', error, stack);
      return false;
    }
  }

  /// Pending grouped notifications that include any of [resolved] are
  /// rebuilt from their payload with the remaining doses (or removed), so
  /// the other doses at that minute still get reminded — even in a
  /// background wake with no household loaded.
  static Future<void> _shrinkGroups(Set<String> resolved) async {
    var shrunk = 0;
    var removed = 0;
    for (final p in await platform.pending()) {
      final payload = ReminderPayload.decode(p.payload);
      if (payload == null || !payload.isGroup) continue;
      if (!payload.doseKeys.any(resolved.contains)) continue;
      await platform.cancel(p.id);
      // tz.local may be unset in a background isolate; the instant is
      // what matters for scheduling, so UTC is fine there.
      final rest = ReminderGroups.without(payload, resolved, tz.UTC);
      if (rest == null) {
        removed++;
        continue;
      }
      shrunk++;
      var exact = false;
      try {
        exact = await platform.canScheduleExact();
      } on Object {
        exact = false;
      }
      await platform.schedule(rest, exact: exact);
    }
    if (shrunk + removed > 0) {
      AppLog.event('reminders.group_shrunk', {
        'kept': shrunk,
        'removed': removed,
        'from': 'push',
      });
    }
  }

  /// Push-resolved keys still ahead of local data; drops stale ones.
  static Future<Set<String>> _readResolved(CareRepository care) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = dayKey(care.now);
      final keep = <String>{};
      for (final key in prefs.getStringList(_resolvedKey) ?? const <String>[]) {
        final split = key.lastIndexOf('|');
        if (split < 0) continue;
        final doseId = key.substring(0, split);
        final day = key.substring(split + 1);
        if (day.compareTo(today) < 0) continue;
        // Once the log is here the plan already leaves the dose out.
        if (care.loggedDose(doseId, day) != null) continue;
        keep.add(key);
      }
      await prefs.setStringList(_resolvedKey, keep.toList());
      return keep;
    } on Object {
      return const {};
    }
  }

  static Future<Map<String, int>> _readRefill(CareRepository care) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final low = {
        for (final m in care.medications)
          if (m.isLow) m.id,
      };
      final result = <String, int>{};
      for (final entry in prefs.getStringList(_refillKey) ?? const <String>[]) {
        final split = entry.indexOf('=');
        if (split < 0) continue;
        final id = entry.substring(0, split);
        final at = int.tryParse(entry.substring(split + 1));
        // Refilled (no longer low): the next low episode notifies again.
        if (at != null && low.contains(id)) result[id] = at;
      }
      return result;
    } on Object {
      return const {};
    }
  }

  static Future<void> _saveRefill(
    List<PlannedNotification> planned,
    Map<String, int> before,
  ) async {
    final next = {...before};
    for (final n in planned) {
      if (n.kind == ReminderKind.refill) {
        next[n.doseId] = n.when.millisecondsSinceEpoch;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_refillKey, [
        for (final e in next.entries) '${e.key}=${e.value}',
      ]);
    } on Object catch (error, stack) {
      AppLog.error('reminders.refill_save_failed', error, stack);
    }
  }

  /// Snooze from the in-app lock screen.
  static Future<bool> snoozeMinutes(
    CareRepository care,
    int minutes, {
    Dose? target,
  }) async {
    try {
      await prepare();
      final dose = target ?? care.nextDue;
      if (dose == null || dose.status != DoseStatus.due) {
        AppLog.event('lock.snooze_skipped', {'reason': 'nothing_due'});
        return false;
      }
      if (permission.value == ReminderPermission.denied) {
        AppLog.event('lock.snooze_skipped', {'reason': 'permission_denied'});
        return false;
      }
      final pet = care.tryPetById(dose.petId);
      final ok = await ReminderSnooze.apply(
        platform,
        ReminderPayload(
          kind: ReminderKind.dose,
          doseId: dose.id,
          day: dayKey(care.now),
          title: ReminderCopy.doseTitle(
            pet?.name ?? 'Your pet',
            dose.name,
            dose.timeLabel,
          ),
        ),
        now: care.now,
        delay: Duration(minutes: minutes),
      );
      if (ok) AppLog.event('lock.snoozed', {'minutes': minutes, 'doseId': dose.id});
      return ok;
    } catch (error, stack) {
      AppLog.error('lock.snooze_failed', error, stack);
      return false;
    }
  }

  /// Handles the tap/action that cold-started the app (after restore).
  static Future<void> handleLaunch() async {
    try {
      await prepare();
      final response = await platform.launchResponse();
      if (response != null) await handleResponse(response, coldStart: true);
    } on Object catch (error, stack) {
      AppLog.error('reminders.launch_failed', error, stack);
    }
  }

  static void _onResponse(ReminderResponse response) {
    AppLog.unawaitedLogged(handleResponse(response), 'reminders.response_failed');
  }

  /// A tap → open that dose; "Given" → log it (with the double-dose
  /// check); "Snooze" (if it reaches the main isolate) → snooze.
  static Future<void> handleResponse(
    ReminderResponse response, {
    bool coldStart = false,
  }) async {
    final payload = ReminderPayload.decode(response.payload);
    final action = response.actionId ?? '';
    AppLog.event('reminders.opened', {
      'kind': payload?.kind.name ?? 'unknown',
      'action': action.isEmpty ? 'tap' : action,
      'coldStart': coldStart,
    });
    if (payload == null) {
      pendingOpen.value = const ReminderOpen();
      return;
    }
    if (action == ReminderActions.snooze) {
      await ReminderSnooze.apply(platform, payload);
      return;
    }
    final care = _care;
    if (action == ReminderActions.given && care != null) {
      await _logFromNotification(care, payload);
      return;
    }
    final today = care == null ? payload.day : dayKey(care.now);
    if (payload.isGroup) {
      if (payload.day != today) {
        AppLog.event('reminders.tap_stale', {
          'doses': payload.group.length,
          'group': true,
        });
      }
      // Several doses: open Today (each has its own Given there).
      pendingOpen.value = payload.day == today
          ? const ReminderOpen()
          : const ReminderOpen(
              message: 'That reminder was for an earlier day — here’s today.',
            );
    } else if (payload.doseId.isEmpty ||
        payload.day.isEmpty ||
        !payload.kind.isDose) {
      pendingOpen.value = const ReminderOpen();
    } else if (payload.day != today) {
      AppLog.event('reminders.tap_stale', {'doseId': payload.doseId});
      pendingOpen.value = const ReminderOpen(
        message: 'That reminder was for an earlier day — here’s today.',
      );
    } else {
      pendingOpen.value = ReminderOpen(doseId: payload.doseId);
    }
  }

  /// "Given" on a notification. Same rules as the log sheet: never logs a
  /// dose someone already logged, never logs a past day's reminder as
  /// today's, and a double tap logs once.
  static Future<void> _logFromNotification(
    CareRepository care,
    ReminderPayload payload,
  ) async {
    final today = dayKey(care.now);
    final fields = {'doseId': payload.doseId, 'kind': payload.kind.name};
    if (payload.day != today) {
      AppLog.event('reminders.given_rejected', {...fields, 'reason': 'stale_day'});
      pendingOpen.value = const ReminderOpen(
        message: 'That reminder was for an earlier day, so nothing was logged.',
      );
      return;
    }
    if (!_logging.add(payload.doseKey)) {
      AppLog.event('reminders.given_rejected', {...fields, 'reason': 'in_flight'});
      return;
    }
    try {
      final existing = care.loggedDose(payload.doseId, today);
      if (existing != null && existing.outcome != LogOutcome.uncertain) {
        await _showAlready(care, payload, existing);
        AppLog.event('reminders.given_rejected', {
          ...fields,
          'reason': 'already_logged',
        });
        return;
      }
      final dose = care.doseById(payload.doseId);
      if (dose == null) {
        AppLog.event('reminders.given_rejected', {...fields, 'reason': 'not_scheduled'});
        pendingOpen.value = const ReminderOpen(
          message: 'That medicine is no longer on today’s schedule.',
        );
        return;
      }
      final ok = await care.logDose(
        doseId: dose.id,
        memberId: care.you.id,
        amount: dose.amount,
        timeLabel: CareRepository.clockLabel(care.now),
      );
      if (ok) {
        AppLog.event('reminders.given', fields);
        pendingOpen.value = ReminderOpen(
          message: 'Logged ${dose.name} for ${care.tryPetById(dose.petId)?.name ?? 'your pet'}.',
        );
        return;
      }
      // Lost the race to another phone (server conflict) or a write error.
      final other = care.loggedDose(payload.doseId, today);
      if (other != null && other.outcome != LogOutcome.uncertain) {
        await _showAlready(care, payload, other);
        AppLog.event('reminders.given_rejected', {...fields, 'reason': 'conflict'});
      } else {
        AppLog.event('reminders.given_failed', fields);
        pendingOpen.value = ReminderOpen(
          doseId: dose.id,
          message: care.lastError ?? 'Couldn’t log that — try again here.',
        );
      }
    } finally {
      _logging.remove(payload.doseKey);
    }
  }

  static Future<void> _showAlready(
    CareRepository care,
    ReminderPayload payload,
    DoseRecord log,
  ) async {
    final medication = care.medicationById(log.medicationId);
    final pet = medication == null ? null : care.tryPetById(medication.petId);
    final member = care.members.where((m) => m.id == log.memberId).firstOrNull;
    final body = ReminderCopy.alreadyBody(
      who: member?.name ?? CareRepository.formerMemberName,
      isYou: member?.isYou ?? false,
      petName: pet?.name ?? 'your pet',
      medName: medication?.name ?? 'this dose',
      timeLabel: log.timeLabel,
      outcome: log.outcome,
    );
    try {
      await platform.show(
        ReminderIds.forDose(ReminderKind.alreadyLogged, payload.doseId, payload.day),
        ReminderCopy.alreadyTitle,
        body,
        kind: ReminderKind.alreadyLogged,
      );
    } on Object catch (error, stack) {
      AppLog.error('reminders.already_show_failed', error, stack);
    }
    pendingOpen.value = ReminderOpen(message: body);
  }

  /// Shows a household update (local fallback when the server can't push).
  static Future<void> showHousehold(String logId, String title, String body) async {
    await prepare();
    await platform.show(
      ReminderIds.of(ReminderKind.household, logId),
      title,
      body,
      kind: ReminderKind.household,
    );
  }
}

extension on ReminderKind {
  bool get isDose =>
      this == ReminderKind.dose ||
      this == ReminderKind.followUp ||
      this == ReminderKind.snooze;
}
