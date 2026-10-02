import 'package:pawsitive_sync/core/constants/release_features.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether What's New was shown for [ReleaseFeatures.version].
abstract final class WhatsNewState {
  static const _key = 'whats_new_seen_version';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) != ReleaseFeatures.version;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, ReleaseFeatures.version);
  }
}
