import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/firebase_setup.dart';
import 'package:pawsitive_sync/firebase_options.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// How the person signed in.
enum AccountProvider { apple, google, email }

/// The outcome of a sign-in attempt. Never an exception: the UI switches on
/// this and always ends in a settled state.
sealed class AccountResult {
  const AccountResult();
}

/// Signed in. [idToken] is a fresh Firebase ID token for the server.
final class AccountSignedIn extends AccountResult {
  const AccountSignedIn({
    required this.idToken,
    required this.provider,
    this.email,
  });

  final String idToken;
  final AccountProvider provider;
  final String? email;
}

/// The person closed the sheet or backed out. Not an error: say nothing.
final class AccountCancelled extends AccountResult {
  const AccountCancelled();
}

/// Something went wrong; [message] is safe to show as is.
final class AccountFailed extends AccountResult {
  const AccountFailed(this.message, {this.code = 'unknown'});

  final String message;

  /// Short machine reason, for logs and tests.
  final String code;
}

/// Optional sign-in (Apple, Google, email) through Firebase Auth. It exists
/// only to bring a household back on a new phone; nothing in the app needs
/// it, so every call is bounded by a timeout and returns an [AccountResult].
abstract final class AccountService {
  static const _timeout = Duration(seconds: 60);
  static const _shortTimeout = Duration(seconds: 15);

  static Future<AccountResult>? _running;
  static Future<void>? _googleReady;

  /// The signed-in account, when Firebase is up and someone is signed in.
  static User? get currentUser =>
      FirebaseSetup.isReady ? FirebaseAuth.instance.currentUser : null;

  /// Apple sign-in is offered on Apple platforms only (App Store 4.8 asks
  /// for it wherever Google sign-in is offered).
  static bool get offersApple =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  static Future<AccountResult> signInWithApple() => _single('apple', _apple);

  static Future<AccountResult> signInWithGoogle() => _single('google', _google);

  static Future<AccountResult> signInWithEmail({
    required String email,
    required String password,
  }) => _emailEntry(email: email, password: password, create: false);

  static Future<AccountResult> createWithEmail({
    required String email,
    required String password,
  }) => _emailEntry(email: email, password: password, create: true);

  /// Checks the fields first, on the phone and instantly, so a typo never
  /// waits on the network or Firebase.
  static Future<AccountResult> _emailEntry({
    required String email,
    required String password,
    required bool create,
  }) async {
    final invalid = checkEmailFields(email: email, password: password);
    if (invalid != null) return invalid;
    return _single(
      create ? 'email_create' : 'email',
      () => _email(email: email, password: password, create: create),
    );
  }

  /// The field problem to show, or null when both look fine.
  static AccountFailed? checkEmailFields({
    required String email,
    required String password,
  }) {
    if (!_looksLikeEmail(email.trim())) {
      return const AccountFailed(
        'Enter a valid email address.',
        code: 'invalid_email',
      );
    }
    if (password.length < 8) {
      return const AccountFailed(
        'Use at least 8 characters for your password.',
        code: 'weak_password',
      );
    }
    return null;
  }

  /// Sends a reset link. Says "sent" even for unknown addresses, so the
  /// screen never reveals which emails have accounts.
  static Future<AccountResult> sendPasswordReset(String email) async {
    final clean = email.trim();
    if (!_looksLikeEmail(clean)) {
      return const AccountFailed(
        'Enter the email you signed up with.',
        code: 'invalid_email',
      );
    }
    if (!await FirebaseSetup.initialize()) return _unavailable();
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: clean)
          .timeout(_shortTimeout);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') return _fromFirebase(error, 'reset');
    } on Object catch (error, stack) {
      AppLog.error('account.reset_failed', error, stack);
      return _offline();
    }
    AppLog.event('account.reset_sent');
    return const AccountCancelled();
  }

  /// A fresh ID token for the signed-in account, or null.
  static Future<String?> freshIdToken() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(true).timeout(_shortTimeout);
    } on Object catch (error, stack) {
      AppLog.error('account.token_failed', error, stack);
      return null;
    }
  }

  /// Which way the current account signs in, for asking it to sign in again.
  static AccountProvider? get currentProvider {
    final ids = currentUser?.providerData.map((info) => info.providerId) ?? [];
    if (ids.contains('apple.com')) return AccountProvider.apple;
    if (ids.contains('google.com')) return AccountProvider.google;
    if (ids.contains('password')) return AccountProvider.email;
    return null;
  }

  /// Deletes the sign-in account itself (App Store 5.1.1(v): deleting the
  /// account deletes the sign-in too). Null when done or nobody is signed
  /// in; [AccountFailed] with code `requires-recent-login` when Firebase
  /// wants a fresh sign-in first, so the caller can ask for one and retry.
  static Future<AccountFailed?> deleteSignInAccount() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      await user.delete().timeout(_shortTimeout);
      AppLog.event('account.sign_in_deleted');
      await signOut();
      return null;
    } on FirebaseAuthException catch (error) {
      return _fromFirebase(error, 'delete');
    } on Object catch (error, stack) {
      AppLog.error('account.sign_in_delete_failed', error, stack);
      return _offline();
    }
  }

  /// Signs out of the account on this phone. The household stays.
  static Future<void> signOut() async {
    try {
      if (_googleReady != null) {
        await GoogleSignIn.instance.signOut().timeout(_shortTimeout);
      }
    } on Object catch (error, stack) {
      AppLog.error('account.google_sign_out_failed', error, stack);
    }
    try {
      if (FirebaseSetup.isReady) await FirebaseAuth.instance.signOut();
      AppLog.event('account.signed_out');
    } on Object catch (error, stack) {
      AppLog.error('account.sign_out_failed', error, stack);
    }
  }

  /// One attempt at a time: a double tap shares the running sheet instead of
  /// opening a second one.
  static Future<AccountResult> _single(
    String provider,
    Future<AccountResult> Function() attempt,
  ) {
    return _running ??= () async {
      AppLog.event('account.sign_in_started', {'provider': provider});
      final AccountResult result;
      if (!await FirebaseSetup.initialize()) {
        result = _unavailable();
      } else {
        result = await attempt().timeout(
          _timeout,
          onTimeout: () => const AccountFailed(
            'Sign-in took too long. Try again.',
            code: 'timeout',
          ),
        );
      }
      AppLog.event('account.sign_in_finished', {
        'provider': provider,
        'result': switch (result) {
          AccountSignedIn() => 'signed_in',
          AccountCancelled() => 'cancelled',
          AccountFailed(:final code) => code,
        },
      });
      return result;
    }().whenComplete(() => _running = null);
  }

  static Future<AccountResult> _apple() async {
    if (!offersApple) {
      return const AccountFailed(
        'Sign in with Apple isn’t available here.',
        code: 'unsupported',
      );
    }
    try {
      if (!await SignInWithApple.isAvailable()) {
        return const AccountFailed(
          'Sign in with Apple isn’t available on this device.',
          code: 'unsupported',
        );
      }
      // A nonce ties Apple's token to this one request (replay protection).
      final rawNonce = _nonce();
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final identityToken = apple.identityToken;
      if (identityToken == null) {
        return const AccountFailed(
          'Apple didn’t return a sign-in. Try again.',
          code: 'no_token',
        );
      }
      final credential = OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
      return _finish(
        await FirebaseAuth.instance.signInWithCredential(credential),
        AccountProvider.apple,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return const AccountCancelled();
      }
      AppLog.event('account.apple_failed', {'code': error.code.name});
      return const AccountFailed(
        'Apple sign-in didn’t finish. Try again.',
        code: 'apple_failed',
      );
    } on FirebaseAuthException catch (error) {
      return _fromFirebase(error, 'apple');
    } on Object catch (error, stack) {
      AppLog.error('account.apple_error', error, stack);
      return const AccountFailed(
        'Apple sign-in didn’t finish. Try again.',
        code: 'apple_error',
      );
    }
  }

  static Future<AccountResult> _google() async {
    try {
      await (_googleReady ??= _initGoogle());
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return const AccountFailed(
          'Google sign-in isn’t available here.',
          code: 'unsupported',
        );
      }
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const AccountFailed(
          'Google didn’t return a sign-in. Try again.',
          code: 'no_token',
        );
      }
      return _finish(
        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        ),
        AccountProvider.google,
      );
    } on GoogleSignInException catch (error) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return const AccountCancelled();
        default:
          AppLog.event('account.google_failed', {'code': error.code.name});
          return const AccountFailed(
            'Google sign-in didn’t finish. Try again.',
            code: 'google_failed',
          );
      }
    } on FirebaseAuthException catch (error) {
      return _fromFirebase(error, 'google');
    } on Object catch (error, stack) {
      // A failed init must be retried next time, not cached as broken.
      _googleReady = null;
      AppLog.error('account.google_error', error, stack);
      return const AccountFailed(
        'Google sign-in didn’t finish. Try again.',
        code: 'google_error',
      );
    }
  }

  /// iOS needs its own client id; Android needs the web client id as the
  /// server client so Firebase can verify the token.
  static Future<void> _initGoogle() {
    final ios = DefaultFirebaseOptions.ios;
    return GoogleSignIn.instance.initialize(
      clientId: !kIsWeb && Platform.isIOS ? ios.iosClientId : null,
      serverClientId: !kIsWeb && Platform.isAndroid
          ? DefaultFirebaseOptions.androidServerClientId
          : null,
    );
  }

  static Future<AccountResult> _email({
    required String email,
    required String password,
    required bool create,
  }) async {
    final clean = email.trim();
    try {
      final auth = FirebaseAuth.instance;
      final credential = create
          ? await auth.createUserWithEmailAndPassword(
              email: clean,
              password: password,
            )
          : await auth.signInWithEmailAndPassword(
              email: clean,
              password: password,
            );
      return _finish(credential, AccountProvider.email);
    } on FirebaseAuthException catch (error) {
      return _fromFirebase(error, create ? 'email_create' : 'email');
    } on Object catch (error, stack) {
      AppLog.error('account.email_error', error, stack);
      return _offline();
    }
  }

  static Future<AccountResult> _finish(
    UserCredential credential,
    AccountProvider provider,
  ) async {
    final user = credential.user;
    final idToken = await user?.getIdToken().timeout(_shortTimeout);
    if (user == null || idToken == null || idToken.isEmpty) {
      return const AccountFailed(
        'Signed in, but we couldn’t confirm it. Try again.',
        code: 'no_id_token',
      );
    }
    return AccountSignedIn(
      idToken: idToken,
      provider: provider,
      email: user.email,
    );
  }

  static AccountFailed _fromFirebase(FirebaseAuthException error, String step) {
    AppLog.event('account.firebase_failed', {'step': step, 'code': error.code});
    return AccountFailed(switch (error.code) {
      'network-request-failed' =>
        'No internet. Check your connection and try again.',
      'too-many-requests' =>
        'Too many tries. Wait a few minutes and try again.',
      'user-disabled' => 'This account has been turned off.',
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' =>
        'That email already has an account. Sign in instead.',
      'weak-password' => 'Use a longer password, at least 8 characters.',
      'wrong-password' ||
      'user-not-found' ||
      'invalid-credential' ||
      'INVALID_LOGIN_CREDENTIALS' => 'That email and password don’t match.',
      'account-exists-with-different-credential' =>
        'That email signs in another way. Try Apple or Google.',
      'operation-not-allowed' => 'This sign-in option is turned off for now.',
      'requires-recent-login' => 'Sign in again to continue.',
      _ => 'Sign-in didn’t finish. Try again.',
    }, code: error.code);
  }

  static AccountFailed _offline() => const AccountFailed(
    'No internet. Check your connection and try again.',
    code: 'offline',
  );

  static AccountFailed _unavailable() => const AccountFailed(
    'Sign-in isn’t available right now. Try again in a moment.',
    code: 'firebase_unavailable',
  );

  static bool _looksLikeEmail(String value) =>
      value.length <= 254 &&
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
