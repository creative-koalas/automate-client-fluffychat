import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_manager.dart';
import 'exceptions.dart';

/// Tokens issued by the main backend. The onboarding chatbot has its own JWT.
class AutomateAuthTokens {
  final String primaryToken;
  final String chatbotToken;
  final String userId;

  AutomateAuthTokens({
    required this.primaryToken,
    required this.chatbotToken,
    required this.userId,
  });
}

class AutomateAuthStore {
  AutomateAuthStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _primaryKey = 'automate_primary_token';
  static const _chatbotKey = 'automate_chatbot_token';
  static const _userIdKey = 'automate_user_id';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens(AutomateAuthTokens tokens) async {
    await _storage.write(key: _primaryKey, value: tokens.primaryToken);
    await _storage.write(key: _chatbotKey, value: tokens.chatbotToken);
    await _storage.write(key: _userIdKey, value: tokens.userId);
  }

  Future<AutomateAuthTokens?> loadTokens() async {
    final primary = await _storage.read(key: _primaryKey);
    final chatbot = await _storage.read(key: _chatbotKey);
    final userId = await _storage.read(key: _userIdKey);
    if (primary == null || chatbot == null || userId == null) return null;
    return AutomateAuthTokens(
      primaryToken: primary,
      chatbotToken: chatbot,
      userId: userId,
    );
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _primaryKey),
      _storage.delete(key: _chatbotKey),
      _storage.delete(key: _userIdKey),
    ]);
  }
}

/// Main backend client for Automate features (singleton).
class AutomateBackend {
  AutomateBackend._({
    http.Client? httpClient,
    AutomateAuthStore? authStore,
    String? chatbotBaseUrl,
    String? mainBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _authStore = authStore ?? AutomateAuthStore(),
        chatbotBaseUrl = chatbotBaseUrl ??
            const String.fromEnvironment(
              'ONBOARDING_CHATBOT_URL',
              defaultValue: 'http://192.168.1.8:3000',
            ),
        mainBackendBaseUrl = mainBaseUrl ??
            const String.fromEnvironment(
              'MAIN_BACKEND_URL',
              defaultValue: 'https://api.automate.example.com',
            );

  static AutomateBackend? _instance;
  static AutomateBackend get instance =>
      _instance ??= AutomateBackend._();

  final http.Client _httpClient;
  final AutomateAuthStore _authStore;
  final String chatbotBaseUrl;
  final String mainBackendBaseUrl;

  String? _primaryToken;
  String? _chatbotToken;

  /// Loads tokens from secure storage into memory.
  Future<void> ensureInitialized() async {
    final tokens = await _authStore.loadTokens();
    if (tokens != null) {
      _applyTokens(tokens);
    }
  }

  Future<void> saveTokens(AutomateAuthTokens tokens) async {
    _applyTokens(tokens);
    await _authStore.saveTokens(tokens);
  }

  Future<void> clearTokens() async {
    _primaryToken = null;
    _chatbotToken = null;
    await _authStore.clear();
  }

  /// Mocked send verification code.
  Future<void> sendVerificationCode(String phoneNumber) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Mocked login/signup that returns tokens using dart-define for chatbot token.
  Future<AuthResponse> loginOrSignup(String phoneNumber, String code) async {
    final auth = AuthResponse(
      token: 'automate-mock-primary-token',
      chatbotToken: _mockChatbotToken,
      userId: phoneNumber.isNotEmpty
          ? phoneNumber
          : DateTime.now().millisecondsSinceEpoch.toString(),
      isNewUser: true,
    );
    await saveTokens(auth.tokens);
    return auth;
  }

  /// Streams chat response from the onboarding chatbot.
  Stream<String> streamChatResponse(String message) async* {
    _ensureChatbotToken();

    final url = Uri.parse('$chatbotBaseUrl/api/submit-user-message');
    final request = http.Request('POST', url);
    request.headers.addAll(_jsonHeaders(forChatbot: true));
    request.body = jsonEncode({'content': message});

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } catch (e) {
      throw AutomateBackendException('无法连接到聊天服务: $e');
    }

    if (_isUnauthorized(response.statusCode)) {
      _notifyUnauthorized();
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AutomateBackendException(
        '聊天请求失败 (${response.statusCode}): ${_extractErrorMessage(body)}',
        statusCode: response.statusCode,
      );
    }

    yield* _parseSseStream(response.stream);
  }

  /// Get input suggestions for autocomplete.
  Future<Map<String, dynamic>> getSuggestions({
    required List<Map<String, String>> previousMessages,
    required String currentInput,
    required int depth,
    required int branchingFactor,
    required Map<String, dynamic> anchoringSuggestions,
  }) async {
    _ensureChatbotToken();

    final url = Uri.parse('$chatbotBaseUrl/api/generate-auto-completions');
    late final http.Response response;
    try {
      response = await _httpClient.post(
        url,
        headers: _jsonHeaders(forChatbot: true),
        body: jsonEncode({
          'history': previousMessages,
          'currentInput': currentInput.trim(),
          'anchoringSuggestions': anchoringSuggestions,
          'treeDepth': depth,
          'branchingFactor': branchingFactor,
        }),
      );
    } catch (e) {
      throw AutomateBackendException('获取补全失败: $e');
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (_isUnauthorized(response.statusCode)) {
      _notifyUnauthorized();
      throw UnauthorizedException();
    }
    if (response.statusCode != 200 || data['ok'] != true) {
      final error = data['error']?.toString() ?? _extractErrorMessage(response.body);
      throw AutomateBackendException(error, statusCode: response.statusCode);
    }

    final suggestions = data['suggestions'];
    if (suggestions is Map<String, dynamic>) return suggestions;
    throw AutomateBackendException('Malformed suggestions payload');
  }

  /// Fetch persisted messages for the current user.
  Future<List<Map<String, String>>> fetchMessages() async {
    _ensureChatbotToken();

    final url = Uri.parse('$chatbotBaseUrl/api/messages');
    late final http.Response response;
    try {
      response = await _httpClient.get(
        url,
        headers: _jsonHeaders(forChatbot: true),
      );
    } catch (e) {
      throw AutomateBackendException('获取历史消息失败: $e');
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (_isUnauthorized(response.statusCode)) {
      _notifyUnauthorized();
      throw UnauthorizedException();
    }
    if (response.statusCode != 200 || data['ok'] != true) {
      final error = data['error']?.toString() ?? _extractErrorMessage(response.body);
      throw AutomateBackendException(error, statusCode: response.statusCode);
    }

    final rawMessages = data['messages'];
    if (rawMessages is List) {
      return rawMessages
          .whereType<Map<String, dynamic>>()
          .map((m) => {
                'role': m['role']?.toString() ?? '',
                'content': m['content']?.toString() ?? '',
              })
          .toList();
    }
    return [];
  }

  void dispose() {
    // shared client; do not close
  }

  // Helpers
  static const String _mockChatbotToken =
      String.fromEnvironment('ONBOARDING_CHATBOT_TOKEN', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjozLCJpYXQiOjE3NjM4OTE4MjIsImV4cCI6MTc2NDQ5NjYyMn0.9Xt4jGGAtB43PZMiR__X8zW9gGooNafyzpyA54gVUHw');

  void _applyTokens(AutomateAuthTokens tokens) {
    _primaryToken = tokens.primaryToken;
    _chatbotToken = tokens.chatbotToken;
  }

  Map<String, String> _jsonHeaders({bool forChatbot = false}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = forChatbot ? _chatbotToken : _primaryToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Stream<String> _parseSseStream(Stream<List<int>> byteStream) async* {
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
            if (delta.isNotEmpty) yield delta;
            break;
          case 'assistant_message':
            final content = _readAssistantContent(event.data);
            if (content.isNotEmpty) yield content;
            break;
          case 'error':
            throw AutomateBackendException(_readErrorFromEvent(event.data));
          case 'done':
            return;
        }
      }
    }
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
    return _SseEvent(name: name!, data: data);
  }

  String _readDelta(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['delta']?.toString() ?? '';
    }
    return data?.toString() ?? '';
  }

  String _readAssistantContent(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['content']?.toString() ?? '';
    }
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

  String _extractErrorMessage(String body) {
    if (body.isEmpty) return 'Unknown error';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            body;
      }
    } catch (_) {}
    return body;
  }

  bool _isUnauthorized(int? status) => status == 401;

  void _notifyUnauthorized() {
    AutomateAuthManager.instance.notifyUnauthorized();
  }

  void _ensureChatbotToken() {
    if (_chatbotToken == null ||
        _chatbotToken!.isEmpty) {
      _notifyUnauthorized();
      throw UnauthorizedException();
    }
  }
}

class _SseEvent {
  final String name;
  final dynamic data;

  _SseEvent({required this.name, required this.data});
}

/// Response from authentication API.
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

  AutomateAuthTokens get tokens => AutomateAuthTokens(
        primaryToken: token,
        chatbotToken: chatbotToken,
        userId: userId,
      );
}
