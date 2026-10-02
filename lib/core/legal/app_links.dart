/// Public URLs required for App Store and Google Play review.
abstract final class AppLinks {
  static const privacy = 'https://pawsitivesync.app/privacy';
  static const terms = 'https://pawsitivesync.app/terms';
  static const eula = 'https://pawsitivesync.app/terms#eula';
  static const support = 'mailto:support@pawsitivesync.app';
  /// Apple subscription management (Guideline 3.1.2).
  static const manageAppleSubscriptions =
      'https://apps.apple.com/account/subscriptions';

  /// Share with sitters — opens join flow with invite code prefilled.
  static String sitterJoinLink(String inviteCode) =>
      'https://pawsitivesync.app/join?code=${Uri.encodeComponent(inviteCode)}';
}
