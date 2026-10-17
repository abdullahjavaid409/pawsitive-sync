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
  ///
  /// If the sign-in already saves another household, nothing moves: the
  /// result is [SignInSaveConflict] and the caller asks the person. Only
  /// then is it called again with [replace] (that household stays on the
  /// server, it just stops coming back with this sign-in).
  Future<SignInSave> saveSignIn(String idToken, {bool replace = false}) =>
      _savingSignIn ??= _saveSignIn(
        idToken,
        replace: replace,
      ).whenComplete(() => _savingSignIn = null);

  Future<SignInSave> _saveSignIn(
    String idToken, {
    required bool replace,
  }) async {
    final api = _api;
    if (api == null) {
      AppLog.event('account.link_skipped', {'reason': 'no_api'});
      return const SignInSaveFailed(
        'Saving needs the online version of the app.',
      );
    }
    if (!isConnected) {
      if (!isPro) {
        // Free never touches the server: nothing to save the account to.
        AppLog.event('account.link_skipped', {'reason': 'free_tier'});
        return const SignInSaveFailed(
          'Saving your household to an account comes with Pro.',
        );
      }
      final error = await connect();
      if (error != null) return SignInSaveFailed(error);
    }
    try {
      await AppLog.trace(
        'account.link',
        () => api.linkAccount(idToken, replace: replace),
      );
      AppLog.event('account.linked', {if (replace) 'replaced': true});
      return const SignInSaved();
    } on HouseholdException catch (error) {
      final conflict = error.accountConflict;
      if (error.isAccountInUse && conflict != null) {
        AppLog.event('account.link_conflict', {
          'pets': conflict.pets,
          'hasLastDay': conflict.lastDay != null,
        });
        return SignInSaveConflict(conflict);
      }
      AppLog.event('account.link_failed', {
        'kind': error.kind.name,
        'code': ?error.code,
        if (replace) 'replace': true,
      });
      return SignInSaveFailed(error.message);
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

/// Outcome of [CareSignIn.saveSignIn].
sealed class SignInSave {
  const SignInSave();
}

/// The sign-in now brings this household back on a new phone.
final class SignInSaved extends SignInSave {
  const SignInSaved();
}

/// Nothing was saved; [message] says why in plain words.
final class SignInSaveFailed extends SignInSave {
  const SignInSaveFailed(this.message);

  final String message;
}

/// The sign-in already saves another household; nothing changed.
final class SignInSaveConflict extends SignInSave {
  const SignInSaveConflict(this.conflict);

  final AccountConflict conflict;
}
