import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AutomateAuthState extends ChangeNotifier {
  AutomateAuthState({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _chatbotKey = 'automate_chatbot_token';
  static const _primaryKey = 'automate_primary_token';
  static const _refreshKey = 'automate_refresh_token';
  static const _expiresAtKey = 'automate_expires_at';
  static const _userIdKey = 'automate_user_id';
  static const _userIdIntKey = 'automate_user_id_int';
  static const _onboardingCompletedKey = 'automate_onboarding_completed';
  static const _matrixAccessTokenKey = 'automate_matrix_access_token';
  static const _matrixUserIdKey = 'automate_matrix_user_id';
  static const _matrixDeviceIdKey = 'automate_matrix_device_id';

  // Token refresh threshold (5 minutes before expiry)
  static const Duration _refreshThreshold = Duration(minutes: 5);

  bool _loggedIn = false;
  String? _chatbotToken;
  String? _primaryToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _userId;
  int? _userIdInt;
  bool _onboardingCompleted = false;
  String? _matrixAccessToken;
  String? _matrixUserId;
  String? _matrixDeviceId;

  bool get isLoggedIn => _loggedIn;
  String? get chatbotToken => _chatbotToken;
  String? get primaryToken => _primaryToken;
  String? get refreshToken => _refreshToken;
  DateTime? get expiresAt => _expiresAt;
  String? get userId => _userId;
  int? get userIdInt => _userIdInt;
  bool get onboardingCompleted => _onboardingCompleted;
  String? get matrixAccessToken => _matrixAccessToken;
  String? get matrixUserId => _matrixUserId;
  String? get matrixDeviceId => _matrixDeviceId;

  /// Check if token is expired
  bool get isTokenExpired {
    if (_expiresAt == null) return true;
    return DateTime.now().isAfter(_expiresAt!);
  }

  /// Check if token is expiring soon (within 5 minutes)
  bool get isTokenExpiringSoon {
    if (_expiresAt == null) return true;
    final timeUntilExpiry = _expiresAt!.difference(DateTime.now());
    return timeUntilExpiry <= _refreshThreshold;
  }

  /// Check if we have a valid (non-expired) token
  bool get hasValidToken {
    return _primaryToken != null && !isTokenExpired;
  }

  Future<void> load() async {
    _primaryToken = await _storage.read(key: _primaryKey);
    _chatbotToken = await _storage.read(key: _chatbotKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    final expiresAtStr = await _storage.read(key: _expiresAtKey);
    _expiresAt = expiresAtStr != null
        ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(expiresAtStr) ?? 0)
        : null;
    _userId = await _storage.read(key: _userIdKey);
    final userIdIntStr = await _storage.read(key: _userIdIntKey);
    _userIdInt = userIdIntStr != null ? int.tryParse(userIdIntStr) : null;
    final onboardingStr = await _storage.read(key: _onboardingCompletedKey);
    _onboardingCompleted = onboardingStr == 'true';
    _matrixAccessToken = await _storage.read(key: _matrixAccessTokenKey);
    _matrixUserId = await _storage.read(key: _matrixUserIdKey);
    _matrixDeviceId = await _storage.read(key: _matrixDeviceIdKey);
    _loggedIn = _primaryToken != null && _chatbotToken != null;
    notifyListeners();
  }

  Future<void> save({
    required String primaryToken,
    required String chatbotToken,
    required String userId,
    required int userIdInt,
    required bool onboardingCompleted,
    String? refreshToken,
    int? expiresIn,
    String? matrixAccessToken,
    String? matrixUserId,
    String? matrixDeviceId,
  }) async {
    _primaryToken = primaryToken;
    _chatbotToken = chatbotToken;
    _userId = userId;
    _userIdInt = userIdInt;
    _onboardingCompleted = onboardingCompleted;
    _loggedIn = true;

    // Handle refresh token
    if (refreshToken != null) {
      _refreshToken = refreshToken;
      await _storage.write(key: _refreshKey, value: refreshToken);
    }

    // Handle token expiry
    if (expiresIn != null) {
      _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await _storage.write(
        key: _expiresAtKey,
        value: _expiresAt!.millisecondsSinceEpoch.toString(),
      );
    }

    // Handle Matrix access token
    if (matrixAccessToken != null) {
      _matrixAccessToken = matrixAccessToken;
      await _storage.write(key: _matrixAccessTokenKey, value: matrixAccessToken);
    }

    // Handle Matrix user ID
    if (matrixUserId != null) {
      _matrixUserId = matrixUserId;
      await _storage.write(key: _matrixUserIdKey, value: matrixUserId);
    }

    // Handle Matrix device ID (CRITICAL for encryption!)
    if (matrixDeviceId != null) {
      _matrixDeviceId = matrixDeviceId;
      await _storage.write(key: _matrixDeviceIdKey, value: matrixDeviceId);
    }

    await _storage.write(key: _primaryKey, value: primaryToken);
    await _storage.write(key: _chatbotKey, value: chatbotToken);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _userIdIntKey, value: userIdInt.toString());
    await _storage.write(key: _onboardingCompletedKey, value: onboardingCompleted.toString());
    notifyListeners();
  }

  /// Update access token after refresh
  Future<void> updateAccessToken(String accessToken, int expiresIn) async {
    _primaryToken = accessToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    await _storage.write(key: _primaryKey, value: accessToken);
    await _storage.write(
      key: _expiresAtKey,
      value: _expiresAt!.millisecondsSinceEpoch.toString(),
    );
    notifyListeners();
  }

  Future<void> markLoggedOut() async {
    _primaryToken = null;
    _chatbotToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _userId = null;
    _userIdInt = null;
    _onboardingCompleted = false;
    _matrixAccessToken = null;
    _matrixUserId = null;
    _matrixDeviceId = null;
    _loggedIn = false;
    await Future.wait([
      _storage.delete(key: _primaryKey),
      _storage.delete(key: _chatbotKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _expiresAtKey),
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _userIdIntKey),
      _storage.delete(key: _onboardingCompletedKey),
      _storage.delete(key: _matrixAccessTokenKey),
      _storage.delete(key: _matrixUserIdKey),
      _storage.delete(key: _matrixDeviceIdKey),
    ]);
    notifyListeners();
  }

  /// 标记用户完成新手引导
  Future<void> markOnboardingCompleted() async {
    _onboardingCompleted = true;
    await _storage.write(key: _onboardingCompletedKey, value: 'true');
    notifyListeners();
  }
}
