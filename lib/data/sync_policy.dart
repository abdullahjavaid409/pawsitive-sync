/// Why a household fetch runs (or is skipped). Logged as `reason`.
enum SyncReason {
  /// Changes made on this phone wait in the outbox.
  pending,

  /// A push (visible or silent) said something changed.
  push,

  /// Pull to refresh / retry button.
  user,

  /// Right after connect or join.
  connected,

  /// The last successful sync is older than [SyncPolicy.maxAge].
  stale,

  /// Never synced on this install (or the clock moved backwards past it).
  never,

  /// Skipped: synced recently and nothing says it changed.
  fresh,

  /// Skipped: the last attempt found no network; backing off.
  noNetwork,
}

/// One decision: fetch or not, and why.
class SyncDecision {
  const SyncDecision(this.sync, this.reason);
  final bool sync;
  final SyncReason reason;

  /// `no_network`, `fresh`, … for log lines.
  String get reasonName => switch (reason) {
    SyncReason.noNetwork => 'no_network',
    _ => reason.name,
  };
}

/// When this phone asks the server for the household: only when it has
/// something to send, something says the server changed, the person asked,
/// or local data is older than [maxAge]. Otherwise local data is used —
/// a normal open makes no network call.
abstract final class SyncPolicy {
  static const maxAge = Duration(minutes: 15);

  /// How far "last synced" may sit in the future before it's distrusted.
  static const clockSkew = Duration(minutes: 2);

  /// After repeated offline failures: 30 s, 1, 2, 4, 8 min, capped at 10.
  static Duration backoff(int failures) {
    if (failures <= 0) return Duration.zero;
    final seconds = 30 * (1 << (failures - 1).clamp(0, 5));
    return Duration(seconds: seconds.clamp(30, 600));
  }

  /// Pure, so every case is table-tested.
  ///
  /// [lastSuccess] in the future means the device clock was moved back:
  /// it can't be trusted, so the data counts as stale.
  static SyncDecision decide({
    required DateTime now,
    required DateTime? lastSuccess,
    bool hasPending = false,
    bool pushSaysChanged = false,
    bool userRequested = false,
    bool justConnected = false,
    int offlineFailures = 0,
    DateTime? lastFailure,
  }) {
    if (userRequested) return const SyncDecision(true, SyncReason.user);
    if (pushSaysChanged) return const SyncDecision(true, SyncReason.push);
    if (justConnected) return const SyncDecision(true, SyncReason.connected);
    // Automatic syncs respect the offline backoff; explicit ones above don't.
    if (offlineFailures > 0 && lastFailure != null) {
      final wait = backoff(offlineFailures);
      final since = now.difference(lastFailure);
      if (!since.isNegative && since < wait) {
        return const SyncDecision(false, SyncReason.noNetwork);
      }
    }
    if (hasPending) return const SyncDecision(true, SyncReason.pending);
    if (lastSuccess == null) return const SyncDecision(true, SyncReason.never);
    final age = now.difference(lastSuccess);
    // A few seconds of clock correction is normal; more is a moved clock.
    if (age < -clockSkew) return const SyncDecision(true, SyncReason.never);
    if (age >= maxAge) return const SyncDecision(true, SyncReason.stale);
    return const SyncDecision(false, SyncReason.fresh);
  }
}
