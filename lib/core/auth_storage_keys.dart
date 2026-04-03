library;

import 'config.dart';

/// Environment-scoped secure-storage keys for auth data.
///
/// Different APP_NAME values (for example `Psygo`, `Psygo_stg`) will map to
/// different key namespaces, preventing cross-environment token overwrite.
abstract class AuthStorageKeys {
  static const String legacyPrimary = 'automate_primary_token';
  static const String legacyRefresh = 'automate_refresh_token';
  static const String legacyExpiresAt = 'automate_expires_at';
  static const String legacyUserId = 'automate_user_id';

  static String get _namespace {
    final raw = PsygoConfig.appName.trim();
    if (raw.isEmpty) return 'psygo';
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  }

  static String _scoped(String key) => '$key::$_namespace';
  static String scoped(String key) => _scoped(key);

  static String get primary => _scoped(legacyPrimary);
  static String get refresh => _scoped(legacyRefresh);
  static String get expiresAt => _scoped(legacyExpiresAt);
  static String get userId => _scoped(legacyUserId);
}
