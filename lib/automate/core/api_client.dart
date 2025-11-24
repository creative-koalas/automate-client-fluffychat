/// Automate API HTTP 客户端
/// 负责与 Automate Assistant 后端通信
library;

import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'config.dart';
import 'token_manager.dart';

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

/// Automate API 客户端
class AutomateApiClient {
  final AutomateTokenManager _tokenManager;
  final http.Client _httpClient;

  AutomateApiClient({
    AutomateTokenManager? tokenManager,
    http.Client? httpClient,
  })  : _tokenManager = tokenManager ?? AutomateTokenManager(),
        _httpClient = httpClient ?? http.Client();

  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(AutomateConfig.baseUrl + path).replace(
      queryParameters: queryParameters,
    );

    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .get(uri, headers: headers)
        .timeout(AutomateConfig.receiveTimeout);

    return _handleResponse<T>(response, fromJsonT);
  }

  /// POST 请求
  Future<ApiResponse<T>> post<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(AutomateConfig.baseUrl + path);
    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(AutomateConfig.receiveTimeout);

    return _handleResponse<T>(response, fromJsonT);
  }

  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, String>? queryParameters,
    T Function(dynamic)? fromJsonT,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse(AutomateConfig.baseUrl + path).replace(
      queryParameters: queryParameters,
    );

    final headers = await _buildHeaders(requiresAuth);

    final response = await _httpClient
        .delete(uri, headers: headers)
        .timeout(AutomateConfig.receiveTimeout);

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
      if (await _tokenManager.isTokenExpiringSoon()) {
        Logs().i('[AutomateApi] Token expiring soon, refreshing...');
        await _refreshAccessToken();
      }

      final accessToken = await _tokenManager.getAccessToken();
      if (accessToken == null) {
        throw ApiException(7, 'No access token available');
      }
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return headers;
  }

  /// 刷新 Access Token
  Future<void> _refreshAccessToken() async {
    final refreshToken = await _tokenManager.getRefreshToken();
    if (refreshToken == null) {
      Logs().e('[AutomateApi] No refresh token available');
      throw ApiException(7, 'No refresh token available');
    }

    try {
      final uri = Uri.parse('${AutomateConfig.baseUrl}/api/matrix/refresh');
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(AutomateConfig.receiveTimeout);

      // Parse response
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 0) {
        final errorMsg = json['msg'] as String? ?? 'Token refresh failed';
        Logs().e('[AutomateApi] Token refresh failed: $errorMsg');
        // Clear tokens on refresh failure
        await _tokenManager.clearTokens();
        throw ApiException(json['code'] as int, errorMsg);
      }

      // Extract new access token
      final data = json['data'] as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int;

      // Update token manager
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await _tokenManager.updateAccessToken(newAccessToken, expiresAt);

      Logs().i('[AutomateApi] Access token refreshed successfully');
    } catch (e) {
      Logs().e('[AutomateApi] Token refresh error: $e');
      // Clear tokens on any error
      await _tokenManager.clearTokens();
      rethrow;
    }
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
        _tokenManager.clearTokens();
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
