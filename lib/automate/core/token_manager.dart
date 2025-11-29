/// JWT Token 管理器
/// 负责 Automate Assistant API 的鉴权 Token 存储和刷新
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT Token 管理器（独立于 Matrix Token）
class AutomateTokenManager {
  static const _storage = FlutterSecureStorage();

  // Storage keys (must match AutomateAuthState keys!)
  static const String _keyAccessToken = 'automate_primary_token'; // NOT automate_access_token!
  static const String _keyRefreshToken = 'automate_refresh_token';
  static const String _keyUserId = 'automate_user_id_int'; // AuthState uses user_id_int for int type
  static const String _keyExpiresAt = 'automate_expires_at';

  // Token 过期前刷新阈值（5 分钟）
  static const Duration _refreshThreshold = Duration(minutes: 5);

  /// 获取访问令牌
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  /// 获取刷新令牌
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// 获取用户 ID
  Future<int?> getUserId() async {
    final userIdStr = await _storage.read(key: _keyUserId);
    return userIdStr != null ? int.tryParse(userIdStr) : null;
  }

  /// 获取过期时间戳
  Future<DateTime?> getExpiresAt() async {
    final expiresAtStr = await _storage.read(key: _keyExpiresAt);
    if (expiresAtStr == null) return null;
    final timestamp = int.tryParse(expiresAtStr);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  /// 保存所有 Token 信息
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int userId,
    required DateTime expiresAt,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyUserId, value: userId.toString()),
      _storage.write(key: _keyExpiresAt, value: expiresAt.millisecondsSinceEpoch.toString()),
    ]);
  }

  /// 更新访问令牌（刷新后）
  Future<void> updateAccessToken(String accessToken, DateTime expiresAt) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyExpiresAt, value: expiresAt.millisecondsSinceEpoch.toString()),
    ]);
  }

  /// 清除所有 Token（登出时调用）
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyExpiresAt),
    ]);
  }

  /// 检查 Token 是否即将过期（提前 5 分钟）
  Future<bool> isTokenExpiringSoon() async {
    final expiresAt = await getExpiresAt();
    if (expiresAt == null) return true;

    final now = DateTime.now();
    final timeUntilExpiry = expiresAt.difference(now);

    return timeUntilExpiry <= _refreshThreshold;
  }

  /// 检查 Token 是否已过期
  Future<bool> isTokenExpired() async {
    final expiresAt = await getExpiresAt();
    if (expiresAt == null) return true;

    return DateTime.now().isAfter(expiresAt);
  }

  /// 检查是否有有效 Token
  Future<bool> hasValidToken() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) return false;

    return !(await isTokenExpired());
  }
}
