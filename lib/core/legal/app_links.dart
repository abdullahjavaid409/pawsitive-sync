import 'package:pawsitive_sync/core/config/app_config.dart';

/// Public URLs required for App Store and Google Play review.
abstract final class AppLinks {
  static const privacy = 'https://pawsitivesync.app/privacy';
  static const terms = 'https://pawsitivesync.app/terms';
  static const eula = 'https://pawsitivesync.app/terms#eula';
  static const support = 'mailto:support@pawsitivesync.app';
  /// Apple subscription management (Guideline 3.1.2).
  static const manageAppleSubscriptions =
      'https://apps.apple.com/account/subscriptions';

  /// App install join — invite code prefilled in the app.
  static String householdJoinLink(String inviteCode) =>
      'https://pawsitivesync.app/join?code=${Uri.encodeComponent(inviteCode)}';

  /// Legacy alias for [householdJoinLink].
  static String sitterJoinLink(String inviteCode) => householdJoinLink(inviteCode);

  /// Browser-only sitter page — log doses without installing the app.
  static String sitterWebLink(String token) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/sitter?t=${Uri.encodeComponent(token)}';
  }
}
