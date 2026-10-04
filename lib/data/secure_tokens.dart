import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets (household bearer token, sitter link token) live in the iOS
/// Keychain / Android Keystore — never in SharedPreferences, which is plain
/// text and included in device backups.
///
/// iOS uses `first_unlock` so reminder and widget code that runs in the
/// background after the first unlock since boot can still read the token.
abstract final class SecureTokens {
  static const householdKey = 'household_token_v1';
  static const sitterKeyPrefix = 'sitter_web_token_v1';

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);

  /// Removes every cached sitter token (household reset / leave).
  static Future<void> deleteSitterTokens() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(sitterKeyPrefix)) await _storage.delete(key: key);
    }
  }
}
