part of 'care_repository.dart';

/// Optional sign-in that keeps a shared household recoverable. The phone is
/// still the source of truth for everything else; these calls only tie a
/// verified account (Firebase ID token) to this member on the server.
///
/// Each method returns a message to show, or null on success, and never
/// throws. A second tap while one is running shares the same attempt.
extension CareSignIn on CareRepository {
  /// Saves this member's sign-in so the household comes back on a new
  /// phone. A Pro owner who never shared gets their household onto the
  /// server first (that is what makes it recoverable); Free stays local.
  Future<String?> saveSignIn(String idToken) =>
      _savingSignIn ??= _saveSignIn(idToken)
          .whenComplete(() => _savingSignIn = null);

  Future<String?> _saveSignIn(String idToken) async {
    final api = _api;
    if (api == null) {
      AppLog.event('account.link_skipped', {'reason': 'no_api'});
      return 'Saving needs the online version of the app.';
    }
    if (!isConnected) {
      if (!isPro) {
        // Free never touches the server: nothing to save the account to.
        AppLog.event('account.link_skipped', {'reason': 'free_tier'});
        return 'Saving your household to an account comes with Pro.';
      }
      final error = await connect();
      if (error != null) return error;
    }
    try {
      await AppLog.trace('account.link', () => api.linkAccount(idToken));
      AppLog.event('account.linked');
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('account.link_failed', {'kind': error.kind.name});
      return error.message;
    }
  }

  /// New phone: brings back the household this sign-in was saved to. The
  /// caller confirms first when this phone already holds its own pets, as
  /// they are replaced by the recovered household.
  Future<String?> recoverWithSignIn(String idToken) async {
    final api = _api;
    if (api == null) {
      AppLog.event('account.recover_skipped', {'reason': 'no_api'});
      return 'Restoring needs the online version of the app.';
    }
    if (isConnected) {
      AppLog.event('account.recover_skipped', {'reason': 'already_connected'});
      return 'This phone is already in a household. Leave it in Settings first.';
    }
    try {
      final session = await AppLog.trace(
        'account.recover',
        () => api.recoverAccount(idToken),
      );
      _applySession(session, joined: true);
      // Same member as before, so RevenueCat finds the same subscription.
      await RevenueCatService.identifyMember(billingUserId);
      syncError = null;
      await _afterConnected();
      AppLog.event('account.recovered', {'pets': pets.length});
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('account.recover_failed', {
        'kind': error.kind.name,
        'code': ?error.code,
      });
      if (error.isNoHousehold) {
        return 'No household is saved to this account yet. On your old '
            'phone, open Settings and save it to your account.';
      }
      return error.message;
    }
  }

  /// Signs out of the account on this phone and, when connected, stops the
  /// account from restoring this membership. The household itself stays.
  Future<void> forgetSignIn() async {
    final api = _api;
    if (api != null && isConnected) {
      try {
        await api.unlinkAccount();
        AppLog.event('account.unlinked');
      } on HouseholdException catch (error) {
        // Signing out locally still happens; the server link is harmless
        // until someone signs in with this account again.
        AppLog.event('account.unlink_failed', {'kind': error.kind.name});
      }
    }
    await AccountService.signOut();
  }
}
