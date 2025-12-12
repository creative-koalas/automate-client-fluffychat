/// Automate 认证服务
/// 负责 Matrix 登录后同步获取 Automate JWT Token
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'config.dart';
import 'token_manager.dart';

/// 认证服务
class PsygoAuthService {
  final AutomateTokenManager _tokenManager;
  final http.Client _httpClient;

  PsygoAuthService({
    AutomateTokenManager? tokenManager,
    http.Client? httpClient,
  })  : _tokenManager = tokenManager ?? AutomateTokenManager(),
        _httpClient = httpClient ?? http.Client();

  /// 使用 Matrix 凭证获取 Automate JWT Token
  ///
  /// [matrixUserId] Matrix 用户 ID（如 @user:domain）
  /// [password] 明文密码
  ///
  /// 成功后自动保存 Token 到 SecureStorage
  ///
  /// 注意：使用 /api/matrix/register 端点（Upsert 模式）
  /// - 用户不存在：自动创建并返回 Token
  /// - 用户已存在：更新密码并返回 Token
  Future<AuthResult> authenticateWithMatrix({
    required String matrixUserId,
    required String password,
  }) async {
    try {
      // 使用 register 端点（Upsert 模式），支持自动创建用户
      final uri = Uri.parse('${PsygoConfig.baseUrl}/api/matrix/register');

      final response = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'matrix_user_id': matrixUserId,
              'password': password,
            }),
          )
          .timeout(PsygoConfig.connectTimeout);

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return AuthResult.failure('Invalid response format');
      }

      final code = json['code'] as int? ?? -1;
      if (code != 0) {
        final msg = json['msg'] as String? ?? 'Unknown error';
        Logs().w('[AutomateAuth] Login failed: $msg');
        return AuthResult.failure(msg);
      }

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) {
        return AuthResult.failure('Empty response data');
      }

      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final expiresIn = data['expires_in'] as int?;
      final userId = data['user_id'] as int?;

      if (accessToken == null ||
          refreshToken == null ||
          expiresIn == null ||
          userId == null) {
        return AuthResult.failure('Missing required fields in response');
      }

      // 计算过期时间
      final expiresAt =
          DateTime.now().add(Duration(seconds: expiresIn));

      // 保存 Token
      await _tokenManager.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
        expiresAt: expiresAt,
      );

      Logs().i('[AutomateAuth] Authentication successful for user: $userId');

      return AuthResult.success(
        accessToken: accessToken,
        userId: userId,
      );
    } catch (e) {
      Logs().e('[AutomateAuth] Authentication error: $e');
      return AuthResult.failure(e.toString());
    }
  }

  /// 检查当前是否有有效的 Automate Token
  Future<bool> hasValidToken() async {
    return await _tokenManager.hasValidToken();
  }

  /// 登出（清除 Token）
  Future<void> logout() async {
    await _tokenManager.clearTokens();
    Logs().i('[AutomateAuth] Logged out, tokens cleared');
  }

  /// 释放资源
  void dispose() {
    _httpClient.close();
  }
}

/// 认证结果
class AuthResult {
  final bool success;
  final String? error;
  final String? accessToken;
  final int? userId;

  AuthResult._({
    required this.success,
    this.error,
    this.accessToken,
    this.userId,
  });

  factory AuthResult.success({
    required String accessToken,
    required int userId,
  }) {
    return AuthResult._(
      success: true,
      accessToken: accessToken,
      userId: userId,
    );
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(
      success: false,
      error: error,
    );
  }
}
