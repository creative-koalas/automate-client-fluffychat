/// Automate API HTTP 客户端（通用版）
/// 负责与 Automate Assistant 后端通信
/// 注意：此客户端用于 Repository 层，直接从 SecureStorage 读取 token
/// 与 backend/api_client.dart 共享相同的 storage keys
library;

import 'dart:convert';
import 'dart:ui';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'config.dart';
import '../utils/custom_http_client.dart';

/// API 响应包装
class ApiResponse<T> {
  final int code;
  final T? data;
  final String message;

  ApiResponse({
    required this.code,
    this.data,
    required this.message,
  });

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse(
      code: json['code'] as int,
      data: fromJsonT != null && json['data'] != null ? fromJsonT(json['data']) : null,
      message: json['msg'] as String? ?? '',
    );
  }
}

/// API 异常
class ApiException implements Exception {
  final int code;
  final String message;

  ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException(code: $code, message: $message)';
}

/// Automate API 客户端（通用版，用于 Repository）
/// 直接从 SecureStorage 读取 token，与 PsygoAuthState 共享相同的 keys
class PsygoApiClient {
  static const _storage = FlutterSecureStorage();

  // Storage keys（必须与 PsygoAuthState 保持一致！）
  static const String _primaryKey = 'automate_primary_token';
  static const String _refreshKey = 'automate_refresh_token';
  static const String _expiresAtKey = 'automate_expires_at';

  // Token 过期前刷新阈值（5 分钟）
  static const Duration _refreshThreshold = Duration(minutes: 5);

  final http.Client _httpClient;

  PsygoApiClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? CustomHttpClient.createHTTPClient();

  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(PsygoConfig.baseUrl + path).replace(
      queryParameters: queryParameters,
    );

    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .get(uri, headers: headers)
        .timeout(PsygoConfig.receiveTimeout);

    return _handleResponse<T>(response, fromJsonT);
  }

  /// POST 请求
  Future<ApiResponse<T>> post<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(PsygoConfig.baseUrl + path);
    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(PsygoConfig.receiveTimeout);

    return _handleResponse<T>(response, fromJsonT);
  }

  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(PsygoConfig.baseUrl + path).replace(
      queryParameters: queryParameters,
    );

    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .delete(uri, headers: headers)
        .timeout(PsygoConfig.receiveTimeout);

    return _handleResponse<T>(response, fromJsonT);
  }

  /// 构建请求头
  Future<Map<String, String>> _buildHeaders(bool requiresAuth) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept-Language': PlatformDispatcher.instance.locale.languageCode,
    };

    if (requiresAuth) {
      // Check if token is expiring soon (within 5 minutes) and refresh if needed
      if (await _isTokenExpiringSoon()) {
        Logs().i('[AutomateApi] Token expiring soon, refreshing...');
        await _refreshAccessToken();
      }

      final accessToken = await _storage.read(key: _primaryKey);
      if (accessToken == null) {
        throw ApiException(7, 'No access token available');
      }
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return headers;
  }

  /// 检查 token 是否即将过期
  Future<bool> _isTokenExpiringSoon() async {
    final expiresAtStr = await _storage.read(key: _expiresAtKey);
    if (expiresAtStr == null) return true;

    final timestamp = int.tryParse(expiresAtStr);
    if (timestamp == null) return true;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeUntilExpiry = expiresAt.difference(DateTime.now());
    return timeUntilExpiry <= _refreshThreshold;
  }

  /// 刷新 Access Token
  Future<void> _refreshAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    if (refreshToken == null) {
      Logs().e('[AutomateApi] No refresh token available');
      throw ApiException(7, 'No refresh token available');
    }

    try {
      final uri = Uri.parse('${PsygoConfig.baseUrl}/api/auth/refresh');
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(PsygoConfig.receiveTimeout);

      // Parse response
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 0) {
        final errorMsg = json['msg'] as String? ?? 'Token refresh failed';
        Logs().e('[AutomateApi] Token refresh failed: $errorMsg');
        // Clear tokens on refresh failure
        await _clearTokens();
        throw ApiException(json['code'] as int, errorMsg);
      }

      // Extract new access token
      final data = json['data'] as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int;

      // Update tokens
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await Future.wait([
        _storage.write(key: _primaryKey, value: newAccessToken),
        _storage.write(key: _expiresAtKey, value: expiresAt.millisecondsSinceEpoch.toString()),
      ]);

      Logs().i('[AutomateApi] Access token refreshed successfully');
    } catch (e) {
      Logs().e('[AutomateApi] Token refresh error: $e');
      // Clear tokens on any error
      await _clearTokens();
      rethrow;
    }
  }

  /// 清除所有 token
  Future<void> _clearTokens() async {
    await Future.wait([
      _storage.delete(key: _primaryKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _expiresAtKey),
    ]);
  }

  /// 处理响应
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJsonT,
  ) {
    // 解析 JSON
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException(-1, 'Invalid JSON response: ${response.body}');
    }

    final apiResponse = ApiResponse<T>.fromJson(json, fromJsonT);

    // 处理业务错误
    if (!apiResponse.isSuccess) {
      // Token 失效（code: 7）
      if (apiResponse.code == 7) {
        Logs().w('[AutomateApi] Invalid token, clearing tokens');
        _clearTokens();
      }
      throw ApiException(apiResponse.code, apiResponse.message);
    }

    return apiResponse;
  }

  /// 关闭客户端
  void dispose() {
    _httpClient.close();
  }
}
