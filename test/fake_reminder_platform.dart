import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_platform.dart';

/// Stands in for flutter_local_notifications: keeps "pending" in memory and
/// records every call so tests can assert what the OS would show.
class FakeReminderPlatform implements ReminderPlatform {
  FakeReminderPlatform({
    this.granted = ReminderPermission.granted,
    this.exact = true,
    this.zone = 'UTC',
  });

  ReminderPermission granted;
  bool exact;
  String zone;
  bool askAnswer = true;
  ReminderResponse? launch;
  void Function(ReminderResponse)? onResponse;

  /// id → notification currently pending.
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  final List<(int, String, String, ReminderKind)> shown = [];
  int scheduleCalls = 0;
  final List<bool> exactFlags = [];

  List<PlannedNotification> ofKind(ReminderKind kind) => [
    for (final n in scheduled.values)
      if (n.kind == kind) n,
  ]..sort((a, b) => a.when.compareTo(b.when));

  @override
  Future<void> initialize(void Function(ReminderResponse) onResponse) async {
    this.onResponse = onResponse;
  }

  @override
  Future<ReminderPermission> permission() async => granted;

  @override
  Future<bool> requestPermission() async {
    granted = askAnswer ? ReminderPermission.granted : ReminderPermission.denied;
    return askAnswer;
  }

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<bool> requestExact() async => exact = true;

  @override
  Future<List<PendingReminder>> pending() async => [
    for (final n in scheduled.values) PendingReminder(n.id, n.payload),
  ];

  @override
  Future<void> schedule(PlannedNotification n, {required bool exact}) async {
    scheduleCalls++;
    exactFlags.add(exact);
    scheduled[n.id] = n;
  }

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    required ReminderKind kind,
    String? payload,
  }) async {
    shown.add((id, title, body, kind));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  int cancelAllCalls = 0;

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<ReminderResponse?> launchResponse() async => launch;

  @override
  Future<String> timezoneName() async => zone;
}
