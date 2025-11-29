import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'auth_state.dart';
import 'exceptions.dart';
import '../core/config.dart';

class AutomateApiClient {
  AutomateApiClient(this.auth, {Dio? dio, http.Client? httpClient})
      : _dio = dio ?? Dio(),
        _http = httpClient ?? http.Client() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            auth.markLoggedOut();
          }
          return handler.next(error);
        },
      ),
    );
  }

  final AutomateAuthState auth;
  final Dio _dio;
  final http.Client _http;

  // K8s NodePort: 30300
  // 构建时通过 --dart-define=ONBOARDING_CHATBOT_URL=http://your-server:30300 指定
  static const String _chatbotBase =
      String.fromEnvironment('ONBOARDING_CHATBOT_URL', defaultValue: 'http://192.168.1.7:30300');

  /// 获取融合认证 Token（供阿里云 SDK 初始化使用）
  Future<FusionAuthTokenResponse> getFusionAuthToken() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '${AutomateConfig.baseUrl}/api/auth/fusion-token',
    );
    final data = res.data ?? {};
    final code = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || code != 0) {
      throw AutomateBackendException(
        data['msg']?.toString() ?? 'Failed to get fusion auth token',
        statusCode: res.statusCode,
      );
    }
    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }
    return FusionAuthTokenResponse(
      verifyToken: respData['verify_token'] as String? ?? '',
      schemeCode: respData['scheme_code'] as String? ?? '',
    );
  }

  /// 发送验证码（暂时 mock）
  Future<void> sendVerificationCode(String phone) async {
    // TODO: 实现真实的验证码发送
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// 手机号登录/注册
  /// [fusionToken]: 融合认证一键登录时传入
  /// [phone] + [code]: 验证码登录时传入
  Future<AuthResponse> loginOrSignup(String phone, String code, {String? fusionToken}) async {
    final body = <String, dynamic>{};
    if (fusionToken != null && fusionToken.isNotEmpty) {
      body['fusion_token'] = fusionToken;
    } else {
      body['phone'] = phone;
      body['code'] = code;
    }

    final res = await _dio.post<Map<String, dynamic>>(
      '${AutomateConfig.baseUrl}/api/auth/phone-login',
      data: body,
    );
    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      throw AutomateBackendException(
        data['msg']?.toString() ?? 'Login failed',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    final authResponse = AuthResponse(
      token: respData['access_token'] as String? ?? '',
      chatbotToken: respData['chatbot_token'] as String? ?? '',
      refreshToken: respData['refresh_token'] as String?,
      expiresIn: respData['expires_in'] as int?,
      userId: respData['username'] as String? ?? '',
      userIdInt: respData['user_id'] as int? ?? 0,
      onboardingCompleted: respData['onboarding_completed'] as bool? ?? false,
      isNewUser: respData['is_new_user'] as bool? ?? false,
      matrixAccessToken: respData['matrix_access_token'] as String?,
      matrixUserId: respData['matrix_user_id'] as String?,
    );

    await auth.save(
      primaryToken: authResponse.token,
      chatbotToken: authResponse.chatbotToken,
      userId: authResponse.userId,
      userIdInt: authResponse.userIdInt,
      onboardingCompleted: authResponse.onboardingCompleted,
      refreshToken: authResponse.refreshToken,
      expiresIn: authResponse.expiresIn,
      matrixAccessToken: authResponse.matrixAccessToken,
      matrixUserId: authResponse.matrixUserId,
    );
    return authResponse;
  }

  /// Refresh the access token using refresh token
  /// Returns true if refresh was successful, false otherwise
  Future<bool> refreshAccessToken() async {
    final refreshToken = auth.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '${AutomateConfig.baseUrl}/api/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final data = res.data ?? {};
      final respCode = data['code'] as int? ?? -1;
      if (res.statusCode != 200 || respCode != 0) {
        // Refresh failed, clear tokens
        await auth.markLoggedOut();
        return false;
      }

      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        await auth.markLoggedOut();
        return false;
      }

      final newAccessToken = respData['access_token'] as String?;
      final newExpiresIn = respData['expires_in'] as int?;

      if (newAccessToken == null || newExpiresIn == null) {
        await auth.markLoggedOut();
        return false;
      }

      await auth.updateAccessToken(newAccessToken, newExpiresIn);
      return true;
    } catch (e) {
      await auth.markLoggedOut();
      return false;
    }
  }

  /// Ensure we have a valid token before making API calls
  /// Will refresh token if it's expiring soon
  Future<bool> ensureValidToken() async {
    // No token at all
    if (!auth.isLoggedIn || auth.primaryToken == null) {
      return false;
    }

    // Token is still valid
    if (auth.hasValidToken && !auth.isTokenExpiringSoon) {
      return true;
    }

    // Token expired or expiring soon, try to refresh
    if (auth.refreshToken != null) {
      return await refreshAccessToken();
    }

    // No refresh token available
    return false;
  }

  Future<Map<String, dynamic>> getSuggestions({
    required List<Map<String, String>> history,
    required String currentInput,
    required int depth,
    required int branchingFactor,
    required Map<String, dynamic> anchoringSuggestions,
  }) async {
    final token = auth.chatbotToken;

    // Truncate the history; take only the last two messages
    final truncatedHistory = history.sublist(max(0, history.length - 2));
    final res = await _dio.post<Map<String, dynamic>>(
      '$_chatbotBase/api/generate-auto-completions',
      data: {
        'history': truncatedHistory,
        'currentInput': currentInput,
        'anchoringSuggestions': anchoringSuggestions,
        'treeDepth': depth,
        'branchingFactor': branchingFactor,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final data = res.data ?? {};
    if (res.statusCode != 200 || data['ok'] != true) {
      throw AutomateBackendException(
        data['error']?.toString() ?? 'Failed to get suggestions',
        statusCode: res.statusCode,
      );
    }
    final suggestions = data['suggestions'];
    if (suggestions is Map<String, dynamic>) return suggestions;
    throw AutomateBackendException('Malformed suggestions payload', statusCode: res.statusCode);
  }

  Future<List<Map<String, String>>> fetchMessages() async {
    final token = auth.chatbotToken;
    final res = await _dio.get<Map<String, dynamic>>(
      '$_chatbotBase/api/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final data = res.data ?? {};
    if (res.statusCode != 200 || data['ok'] != true) {
      throw AutomateBackendException(
        data['error']?.toString() ?? 'Failed to fetch messages',
        statusCode: res.statusCode,
      );
    }
    final rawMessages = data['messages'];
    if (rawMessages is List) {
      return rawMessages
          .whereType<Map<String, dynamic>>()
          .map((m) => {
                'role': m['role']?.toString() ?? '',
                'content': m['content']?.toString() ?? '',
              },)
          .toList();
    }
    return [];
  }

  /// 标记用户完成新手引导
  Future<void> completeOnboarding() async {
    final userIdInt = auth.userIdInt;
    if (userIdInt == null || userIdInt == 0) {
      throw AutomateBackendException('User ID not found');
    }

    final token = auth.primaryToken;
    final res = await _dio.post<Map<String, dynamic>>(
      '${AutomateConfig.baseUrl}/api/users/$userIdInt/complete-onboarding',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      throw AutomateBackendException(
        data['msg']?.toString() ?? 'Failed to complete onboarding',
        statusCode: res.statusCode,
      );
    }

    // 更新本地状态
    await auth.markOnboardingCompleted();
  }

  Stream<ChatStreamEvent> streamChatResponse(String message) async* {
    final token = auth.chatbotToken;
    final url = Uri.parse('$_chatbotBase/api/submit-user-message');
    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';
    request.body = jsonEncode({'content': message});

    late final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } catch (e) {
      throw AutomateBackendException('无法连接到聊天服务: $e');
    }

    if (response.statusCode == 401) {
      auth.markLoggedOut();
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AutomateBackendException(
        '聊天请求失败 (${response.statusCode}): $body',
        statusCode: response.statusCode,
      );
    }

    yield* _parseSseStream(response.stream);
  }

  Stream<ChatStreamEvent> _parseSseStream(Stream<List<int>> byteStream) async* {
    final decoder = utf8.decoder;
    var buffer = '';
    await for (final chunk in byteStream.transform(decoder)) {
      buffer += chunk;
      int boundary;
      while ((boundary = buffer.indexOf('\n\n')) != -1) {
        final rawEvent = buffer.substring(0, boundary);
        buffer = buffer.substring(boundary + 2);
        final event = _decodeSseEvent(rawEvent);
        if (event == null) continue;
        switch (event.name) {
          case 'assistant_message_delta':
            final delta = _readDelta(event.data);
            if (delta.isNotEmpty) yield ChatStreamEvent.delta(delta);
            break;
          case 'decision':
            final shouldStop = _readDecision(event.data);
            yield ChatStreamEvent.decision(shouldStop);
            break;
          case 'assistant_message':
            final content = _readAssistantContent(event.data);
            if (content.isNotEmpty) yield ChatStreamEvent.assistantMessage(content);
            break;
          case 'error':
            throw AutomateBackendException(_readErrorFromEvent(event.data));
          case 'done':
            yield ChatStreamEvent.done();
            return;
        }
      }
    }
  }

  bool _readDecision(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['shouldStop'] == true;
    }
    return false;
  }

  _SseEvent? _decodeSseEvent(String rawEvent) {
    String? name;
    final dataBuffer = StringBuffer();
    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        name = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataBuffer.write(line.substring(5).trim());
      }
    }
    if (name == null) return null;
    final dataString = dataBuffer.toString();
    dynamic data;
    if (dataString.isNotEmpty) {
      try {
        data = jsonDecode(dataString);
      } catch (_) {
        data = dataString;
      }
    }
    return _SseEvent(name: name, data: data);
  }

  String _readDelta(dynamic data) {
    if (data is Map<String, dynamic>) return data['delta']?.toString() ?? '';
    return data?.toString() ?? '';
  }

  String _readAssistantContent(dynamic data) {
    if (data is Map<String, dynamic>) return data['content']?.toString() ?? '';
    return '';
  }

  String _readErrorFromEvent(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['message']?.toString() ??
          data['error']?.toString() ??
          'Unknown error';
    }
    return data?.toString() ?? 'Unknown error';
  }
}

class AuthResponse {
  final String token;
  final String chatbotToken;
  final String? refreshToken;
  final int? expiresIn;
  final String userId;
  final int userIdInt;
  final bool onboardingCompleted;
  final bool isNewUser;
  final String? matrixAccessToken;
  final String? matrixUserId;

  AuthResponse({
    required this.token,
    required this.chatbotToken,
    this.refreshToken,
    this.expiresIn,
    required this.userId,
    required this.userIdInt,
    required this.onboardingCompleted,
    required this.isNewUser,
    this.matrixAccessToken,
    this.matrixUserId,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'chatbotToken': chatbotToken,
        'refreshToken': refreshToken,
        'expiresIn': expiresIn,
        'userId': userId,
        'userIdInt': userIdInt,
        'onboardingCompleted': onboardingCompleted,
        'isNewUser': isNewUser,
        'matrixAccessToken': matrixAccessToken,
        'matrixUserId': matrixUserId,
      };
}

/// 融合认证 Token 响应
class FusionAuthTokenResponse {
  final String verifyToken;
  final String schemeCode;

  FusionAuthTokenResponse({
    required this.verifyToken,
    required this.schemeCode,
  });
}

class _SseEvent {
  final String name;
  final dynamic data;

  _SseEvent({required this.name, required this.data});
}

/// SSE 事件类型枚举
enum ChatStreamEventType {
  /// 对话 LLM 的增量内容
  delta,
  /// 判断 LLM 的决策结果
  decision,
  /// 完整的 assistant 消息（流结束时）
  assistantMessage,
  /// 流结束
  done,
}

/// 聊天流事件
class ChatStreamEvent {
  final ChatStreamEventType type;
  /// delta 类型时为增量文本，assistantMessage 类型时为完整内容
  final String? content;
  /// decision 类型时为 true/false
  final bool? shouldStop;

  ChatStreamEvent._({
    required this.type,
    this.content,
    this.shouldStop,
  });

  factory ChatStreamEvent.delta(String content) => ChatStreamEvent._(
        type: ChatStreamEventType.delta,
        content: content,
      );

  factory ChatStreamEvent.decision(bool shouldStop) => ChatStreamEvent._(
        type: ChatStreamEventType.decision,
        shouldStop: shouldStop,
      );

  factory ChatStreamEvent.assistantMessage(String content) => ChatStreamEvent._(
        type: ChatStreamEventType.assistantMessage,
        content: content,
      );

  factory ChatStreamEvent.done() => ChatStreamEvent._(
        type: ChatStreamEventType.done,
      );
}
