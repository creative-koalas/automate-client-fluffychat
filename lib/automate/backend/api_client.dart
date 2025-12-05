import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  // 或者通过 K8S_NODE_IP 自动构建
  static const String _chatbotBase =
      String.fromEnvironment('ONBOARDING_CHATBOT_URL',
        defaultValue: 'http://${AutomateConfig.k8sNodeIp}:30300');

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
      matrixDeviceId: respData['matrix_device_id'] as String?,
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
      matrixDeviceId: authResponse.matrixDeviceId,
    );
    return authResponse;
  }

  /// 验证手机号（新登录流程第一步）
  /// 返回是否新用户 + pending_token
  Future<VerifyPhoneResponse> verifyPhone(String fusionToken) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '${AutomateConfig.baseUrl}/api/auth/verify-phone',
      data: {'fusion_token': fusionToken},
    );
    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      throw AutomateBackendException(
        data['msg']?.toString() ?? 'Phone verification failed',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return VerifyPhoneResponse(
      phone: respData['phone'] as String? ?? '',
      isNewUser: respData['is_new_user'] as bool? ?? false,
      pendingToken: respData['pending_token'] as String? ?? '',
    );
  }

  /// 完成登录/注册（新登录流程第二步）
  /// 新用户需要传入邀请码
  Future<AuthResponse> completeLogin(String pendingToken, {String? invitationCode}) async {
    final body = <String, dynamic>{
      'pending_token': pendingToken,
    };
    if (invitationCode != null && invitationCode.isNotEmpty) {
      body['invitation_code'] = invitationCode;
    }

    final res = await _dio.post<Map<String, dynamic>>(
      '${AutomateConfig.baseUrl}/api/auth/complete-login',
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
      matrixDeviceId: respData['matrix_device_id'] as String?,
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
      matrixDeviceId: authResponse.matrixDeviceId,
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

    // Performance metrics - start timing
    final startTime = DateTime.now().millisecondsSinceEpoch;

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

    // Performance metrics - calculate timing
    final clientTotalMs = DateTime.now().millisecondsSinceEpoch - startTime;

    final data = res.data ?? {};
    if (res.statusCode != 200 || data['ok'] != true) {
      throw AutomateBackendException(
        data['error']?.toString() ?? 'Failed to get suggestions',
        statusCode: res.statusCode,
      );
    }

    // Extract server-side timings
    final timings = data['_timings'] as Map<String, dynamic>?;
    final serverTotalMs = timings?['total_ms'] as int?;
    final llmMs = timings?['llm_ms'] as int?;
    final dbMs = timings?['db_ms'] as int?;
    final networkMs = serverTotalMs != null ? clientTotalMs - serverTotalMs : null;

    // Print performance analysis
    debugPrint('[auto-completion 耗时分析] {');
    debugPrint('  client_total_ms: $clientTotalMs,  // 客户端感知的总耗时');
    debugPrint('  server_total_ms: $serverTotalMs,  // 服务端处理耗时');
    debugPrint('  network_ms: $networkMs,  // 网络往返耗时');
    debugPrint('  llm_ms: $llmMs,  // DeepSeek API 耗时');
    debugPrint('  db_ms: $dbMs,  // 数据库耗时');
    debugPrint('}');

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

  /// 完成新手引导并创建首个 Agent
  /// 返回创建的 Agent 信息（agent_id, matrix_user_id, pod_url）
  Future<OnboardingResult> completeOnboarding() async {
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

    // 解析返回的 Agent 信息
    final respData = data['data'] as Map<String, dynamic>?;
    return OnboardingResult(
      agentId: respData?['agent_id'] as String? ?? '',
      matrixUserId: respData?['matrix_user_id'] as String? ?? '',
      podUrl: respData?['pod_url'] as String? ?? '',
    );
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
  final String? matrixDeviceId;

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
    this.matrixDeviceId,
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
        'matrixDeviceId': matrixDeviceId,
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

/// 验证手机号响应
class VerifyPhoneResponse {
  final String phone;       // 脱敏手机号（138****1234）
  final bool isNewUser;     // 是否新用户
  final String pendingToken; // 待确认 token（5分钟有效）

  VerifyPhoneResponse({
    required this.phone,
    required this.isNewUser,
    required this.pendingToken,
  });
}

/// 新手引导完成结果（包含创建的 Agent 信息）
class OnboardingResult {
  final String agentId;
  final String matrixUserId;
  final String podUrl;

  OnboardingResult({
    required this.agentId,
    required this.matrixUserId,
    required this.podUrl,
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
