import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'auth_state.dart';
import 'exceptions.dart';

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
      String.fromEnvironment('ONBOARDING_CHATBOT_URL', defaultValue: 'http://192.168.1.4:30300');

  Future<void> sendVerificationCode(String phone) async {
    // Mock: assume success
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<AuthResponse> loginOrSignup(String phone, String code) async {
    const chatbotToken =
        String.fromEnvironment('ONBOARDING_CHATBOT_TOKEN', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxLCJpYXQiOjE3NjQyNDgwNDAsImV4cCI6MTc2NDg1Mjg0MH0.XiYa82GX197DEm8IYPRhCbJAQiFT3jz0wjTavElhxOg');
    final authResponse = AuthResponse(
      token: 'automate-mock-primary-token',
      chatbotToken: chatbotToken,
      userId: phone.isNotEmpty ? phone : DateTime.now().millisecondsSinceEpoch.toString(),
      isNewUser: true,
    );
    await auth.save(
      primaryToken: authResponse.token,
      chatbotToken: authResponse.chatbotToken,
      userId: authResponse.userId,
    );
    return authResponse;
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
  final String userId;
  final bool isNewUser;

  AuthResponse({
    required this.token,
    required this.chatbotToken,
    required this.userId,
    required this.isNewUser,
  });

  Map<String, String> toJson() => {
        'token': token,
        'chatbotToken': chatbotToken,
        'userId': userId,
      };
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
