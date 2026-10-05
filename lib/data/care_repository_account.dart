part of 'care_repository.dart';

/// Who a delete affects, for the confirm copy and the logs.
enum AccountDeleteScope { household, member, local }

/// Set while a server delete is in flight. If the app is killed or
/// suspended between the server deleting and the phone wiping, the next
/// launch sees it and finishes the job (the retry gets 401 → local wipe).
const _deletePendingKey = 'account_delete_pending_v1';

/// Account deletion (App Store / Play requirement). Server first, then the
/// phone: nothing is removed locally unless the server confirmed (or already
/// forgot this phone), so a failed delete never leaves half an account.
extension CareAccount on CareRepository {
  AccountDeleteScope get accountDeleteScope {
    if (!isConnected) return AccountDeleteScope.local;
    return you.role == MemberRole.owner
        ? AccountDeleteScope.household
        : AccountDeleteScope.member;
  }

  /// A delete started on a previous run never finished (see
  /// [_deletePendingKey]); `bootstrap` calls [deleteAccount] again.
  bool get accountDeletePending => _accountDeletePending;

  /// Deletes the account. Returns a message (and deletes nothing) when it
  /// could not; null once everything is gone. A second tap while one is
  /// running gets the same result instead of a second request.
  Future<String?> deleteAccount() =>
      _deleting ??= _deleteAccount().whenComplete(() => _deleting = null);

  Future<String?> _deleteAccount() async {
    lastError = null;
    var scope = accountDeleteScope;
    AppLog.event('account.delete_requested', {
      'scope': scope.name,
      if (_accountDeletePending) 'resumed': true,
    });
    final api = _api;
    if (api != null && isConnected) {
      await _setDeletePending(true);
      try {
        final answer = await AppLog.trace('account.delete', api.deleteAccount);
        scope = answer == 'household'
            ? AccountDeleteScope.household
            : AccountDeleteScope.member;
      } on HouseholdException catch (error) {
        // 401: the server no longer knows this phone (deleted by an earlier
        // try whose answer was lost, or the household is gone) — finish here.
        if (error.kind != HouseholdErrorKind.unauthorized) {
          // The person is told and decides to retry; never auto-delete on a
          // later launch after they saw a failure.
          await _setDeletePending(false);
          AppLog.event('account.delete_failed', {
            'kind': error.timedOut ? 'timeout' : error.kind.name,
            if (error.status != null) 'status': error.status,
          });
          lastError = switch (error) {
            // Sent but unanswered: the server may or may not have deleted.
            // Wiping now could orphan a live account; a retry is safe.
            HouseholdException(timedOut: true) => "Couldn’t confirm the delete — check your connection and try again.",
            HouseholdException(kind: HouseholdErrorKind.offline) => "Can’t reach the server, so nothing was deleted. Connect to the internet and try again.",
            _ => "Couldn’t delete your account right now. Nothing was deleted. Try again in a moment.",
          };
          _notify();
          return lastError;
        }
        AppLog.event('account.delete_already_gone', {'scope': scope.name});
      }
    }
    // Solo phones (or no household at all) have nothing on the server; any
    // queued outbox ops are discarded by the wipe, never sent.
    // One line for the whole delete: account.deleted (not also account.wiped).
    await _wipe();
    AppLog.event('account.deleted', {'scope': scope.name});
    return null;
  }

  Future<void> _setDeletePending(bool pending) async {
    _accountDeletePending = pending;
    try {
      final prefs = await SharedPreferences.getInstance();
      pending
          ? await prefs.setBool(_deletePendingKey, true)
          : await prefs.remove(_deletePendingKey);
    } on Object catch (error, stack) {
      // Only the kill-mid-delete recovery is lost; the delete still runs.
      AppLog.error('account.pending_flag_failed', error, stack);
    }
  }

  /// Removes everything this app stored on the phone: household database,
  /// tokens, queue, events, photos, setup answers, reminders, widget, analytics.
  /// Each step is isolated so one failure (Keychain locked, RevenueCat
  /// offline) never leaves the rest behind.
  Future<void> wipeDevice() async {
    await _wipe();
    AppLog.event('account.wiped');
  }

  Future<void> _wipe() async {
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (error, stack) {
        AppLog.error('account.wipe_step_failed', error, stack, {'step': name});
      }
    }

    await step('reminders', DoseReminders.cancel);
    // Household, tokens, outbox, events, photos, RevenueCat logOut (which
    // swallows its own failures and times out on a slow link).
    await step('household', reset);
    // The rows are gone after reset; remove the file itself (and any damaged
    // copy set aside) so nothing of the household stays on the phone.
    await step('database', LocalDatabase.shared.deleteFile);
    await step('secure_tokens', SecureTokens.deleteAll);
    await step('reminder_choice', ReminderChoice.clear);
    await step('onboarding', OnboardingState.clear);
    await step('whats_new', WhatsNewState.clear);
    await step('push', PushService.clearLocal);
    await step('widget', AppleWidgets.clear);
    await step('analytics', () async => AnalyticsService.clear());
    // Last sweep: any preference a future store forgets to clear (also
    // removes the delete-pending flag).
    await step('prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });
    _accountDeletePending = false;
  }
}
