import 'package:pawsitive_sync/core/config/app_config.dart';

/// Public URLs required for App Store and Google Play review.
abstract final class AppLinks {
  /// Must match the Privacy Policy URL in App Store Connect.
  static const privacy = 'https://sites.google.com/view/pawasitive/home';

  /// Apple's standard EULA — the default for App Store subscriptions.
  static const terms =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const eula = terms;
  static const support = 'mailto:workplace0331@gmail.com';

  /// Apple subscription management (Guideline 3.1.2).
  static const manageAppleSubscriptions =
      'https://apps.apple.com/account/subscriptions';

  /// App Store page to install from; the invite code is entered in the app.
  /// Null until [AppConfig.appStoreId] is set, so we never share a dead link.
  static String? householdJoinLink(String inviteCode) =>
      AppConfig.appStoreId.isEmpty
      ? null
      : 'https://apps.apple.com/app/id${AppConfig.appStoreId}';

  /// Browser-only sitter page — log doses without installing the app.
  /// The token rides in the fragment (`#t=`), which browsers never send to
  /// the server, so it stays out of proxy and access logs.
  static String sitterWebLink(String token) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/sitter#t=${Uri.encodeComponent(token)}';
  }
}
