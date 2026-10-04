part of 'care_repository.dart';

/// Who a delete affects, for the confirm copy and the logs.
enum AccountDeleteScope { household, member, local }

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

  /// Deletes the account. Returns a message (and deletes nothing) when it
  /// could not; null once everything is gone.
  Future<String?> deleteAccount() async {
    lastError = null;
    var scope = accountDeleteScope;
    AppLog.event('account.delete_requested', {'scope': scope.name});
    final api = _api;
    if (api != null && isConnected) {
      try {
        final answer = await AppLog.trace('account.delete', api.deleteAccount);
        scope = answer == 'household'
            ? AccountDeleteScope.household
            : AccountDeleteScope.member;
      } on HouseholdException catch (error) {
        // 401: the server no longer knows this phone — already deleted.
        if (error.kind != HouseholdErrorKind.unauthorized) {
          AppLog.event('account.delete_failed', {
            'kind': error.kind.name,
            if (error.status != null) 'status': error.status,
          });
          lastError = error.kind == HouseholdErrorKind.offline
              ? "Can't reach the server. Connect to the internet to delete your account. Nothing was deleted."
              : "Couldn't delete your account right now. Nothing was deleted. Try again in a moment.";
          _notify();
          return lastError;
        }
        AppLog.event('account.delete_already_gone', {'scope': scope.name});
      }
    }
    await wipeDevice();
    AppLog.event('account.deleted', {'scope': scope.name});
    return null;
  }

  /// Removes everything this app stored on the phone: household, tokens,
  /// queue, events, photos, setup answers, reminders, widget, analytics.
  Future<void> wipeDevice() async {
    await DoseReminders.cancel();
    await reset();
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (error, stack) {
        AppLog.error('account.wipe_step_failed', error, stack, {'step': name});
      }
    }

    await step('secure_tokens', SecureTokens.deleteAll);
    await step('reminder_choice', ReminderChoice.clear);
    await step('onboarding', OnboardingState.clear);
    await step('whats_new', WhatsNewState.clear);
    await step('push', PushService.clearLocal);
    await step('widget', AppleWidgets.clear);
    await step('analytics', () async => AnalyticsService.clear());
    // Last sweep: any preference a future store forgets to clear.
    await step('prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });
    AppLog.event('account.wiped');
  }
}
