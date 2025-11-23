/// Backend API wrapper for Automate functionality.
/// This file contains HTTP API clients and mock implementations
/// for the onboarding chatbot and other automation features.
library;

import 'dart:async';
import 'package:http/http.dart' as http;

/// Main backend client for Automate features
class AutomateBackend {
  // TODO: Replace with actual backend URL
  static const String baseUrl = 'https://api.automate.example.com';

  final http.Client _httpClient;

  AutomateBackend({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Streams chat response from the AI chatbot.
  ///
  /// API Design:
  /// POST /api/v1/chat/stream
  /// Request body: {
  ///   "message": "user message text",
  ///   "session_id": "optional session identifier",
  ///   "context": {
  ///     "is_onboarding": true,
  ///     "user_id": "optional user ID"
  ///   }
  /// }
  ///
  /// Response: Server-Sent Events (SSE) stream
  /// Each event: data: {"chunk": "text chunk", "done": false}
  /// Final event: data: {"chunk": "", "done": true}
  Stream<String> streamChatResponse(
    String message, {
    String? sessionId,
    bool isOnboarding = true,
  }) async* {
    // TODO: Implement actual API call
    // For now, using mock implementation
    yield* _mockStreamChatResponse(message);

    /* Actual implementation would look like:
    final url = Uri.parse('$baseUrl/api/v1/chat/stream');
    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'message': message,
      'session_id': sessionId,
      'context': {
        'is_onboarding': isOnboarding,
      },
    });

    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw AutomateBackendException(
        'Failed to stream chat response: ${response.statusCode}',
      );
    }

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      // Parse SSE format
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6);
          final data = jsonDecode(jsonStr);
          if (!data['done']) {
            yield data['chunk'] as String;
          }
        }
      }
    }
    */
  }

  /// Mock implementation of streaming chat response
  /// Simulates AI responses with realistic typing speed
  Stream<String> _mockStreamChatResponse(String message) async* {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    // Generate mock response based on message content
    final response = _generateMockResponse(message);

    // Stream the response character by character with realistic delays
    final words = response.split(' ');
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      yield word;

      // Add space after word (except last word)
      if (i < words.length - 1) {
        yield ' ';
      }

      // Variable delay to simulate typing
      final delay = word.length * 20 + (word.contains('。') ? 200 : 50);
      await Future.delayed(Duration(milliseconds: delay));
    }
  }

  /// Generate mock response based on user input
  String _generateMockResponse(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('提醒') || lowerMessage.contains('remind')) {
      return '好的！我可以帮你设置定时提醒。\n\n'
          '我会在指定的时间通过通知提醒你。你想在什么时间收到提醒呢？\n\n'
          '例如："每天早上 8 点" 或 "每周一下午 3 点"';
    } else if (lowerMessage.contains('整理') || lowerMessage.contains('organize')) {
      return '明白了！我可以帮你整理和管理待办事项。\n\n'
          '我会自动分类、优先排序，还可以设置提醒。\n\n'
          '你想让我怎么帮你整理呢？';
    } else if (lowerMessage.contains('监控') || lowerMessage.contains('monitor') ||
               lowerMessage.contains('价格') || lowerMessage.contains('price')) {
      return '好的！我可以帮你监控网站或价格变化。\n\n'
          '我会定期检查并在发现变化时通知你。\n\n'
          '请告诉我你想监控的网站地址或商品链接。';
    } else if (lowerMessage.contains('邮件') || lowerMessage.contains('email')) {
      return '我可以帮你管理邮件！\n\n'
          '包括自动分类、智能回复建议、重要邮件提醒等。\n\n'
          '你需要哪方面的帮助呢？';
    } else {
      return '我理解了！听起来是个很有趣的任务。\n\n'
          '让我帮你设置这个自动化任务。我需要了解更多细节：\n\n'
          '1. 具体的触发条件是什么？\n'
          '2. 你希望多久执行一次？\n'
          '3. 需要什么样的通知方式？\n\n'
          '请告诉我更多细节，我会为你定制最合适的方案。';
    }
  }

  /// Get input suggestions for autocomplete
  ///
  /// API Design:
  /// POST /api/v1/chat/suggestions
  /// Request body: {
  ///   "previous_messages": [
  ///     {"role": "user", "content": "..."},
  ///     {"role": "assistant", "content": "..."}
  ///   ],
  ///   "current_input": "我今天",
  ///   "depth": 2,
  ///   "branching_factor": 3,
  ///   "anchoring_suggestions": {
  ///     "吃了": null,
  ///     "心情": null,
  ///     "想要": null
  ///   }
  /// }
  ///
  /// Response: {
  ///   "suggestions": {
  ///     "吃了": {"苹果": null, "香蕉": null, "梨": null},
  ///     "心情": {"很好": null, "很糟": null, "还可以": null},
  ///     "想要": {"出去玩": null, "学习": null, "上班": null}
  ///   }
  /// }
  Future<Map<String, dynamic>> getSuggestions({
    required List<Map<String, String>> previousMessages,
    required String currentInput,
    required int depth,
    required int branchingFactor,
    required Map<String, dynamic> anchoringSuggestions,
  }) async {
    // TODO: Implement actual API call
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));

    // For now, using mock implementation
    return _mockGetSuggestions(
      currentInput: currentInput,
      depth: depth,
      branchingFactor: branchingFactor,
      anchoringSuggestions: anchoringSuggestions,
    );

    /* Actual implementation:
    final url = Uri.parse('$baseUrl/api/v1/chat/suggestions');
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'previous_messages': previousMessages,
        'current_input': currentInput,
        'depth': depth,
        'branching_factor': branchingFactor,
        'anchoring_suggestions': anchoringSuggestions,
      }),
    );

    if (response.statusCode != 200) {
      throw AutomateBackendException(
        'Failed to get suggestions: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    return data['suggestions'] as Map<String, dynamic>;
    */
  }

  /// Mock implementation of getSuggestions
  /// If anchoring is empty: create NEW tree with given depth
  /// If anchoring has structure: EXTEND the tree by adding depth levels to terminal nodes
  Map<String, dynamic> _mockGetSuggestions({
    required String currentInput,
    required int depth,
    required int branchingFactor,
    required Map<String, dynamic> anchoringSuggestions,
  }) {
    // If no anchoring provided, create a new tree from scratch
    if (anchoringSuggestions.isEmpty) {
      final defaultAnchors = {'我想': null, '我要': null, '帮我': null};
      return _buildNewTree(
        anchors: defaultAnchors,
        depth: depth,
        branchingFactor: branchingFactor,
        currentInput: currentInput,
      );
    }

    // Otherwise, extend the existing tree structure
    return _extendTree(
      tree: anchoringSuggestions,
      depth: depth,
      branchingFactor: branchingFactor,
      currentInput: currentInput,
    );
  }

  /// Build a completely new tree
  Map<String, dynamic> _buildNewTree({
    required Map<String, dynamic> anchors,
    required int depth,
    required int branchingFactor,
    required String currentInput,
  }) {
    final result = <String, dynamic>{};

    for (final anchor in anchors.keys) {
      if (depth <= 1) {
        result[anchor] = null;
      } else {
        result[anchor] = _generateMockSuggestionChildren(
          parent: anchor,
          currentInput: currentInput,
          depth: depth - 1,
          branchingFactor: branchingFactor,
        );
      }
    }

    return result;
  }

  /// Extend an existing tree by adding levels to terminal nodes
  Map<String, dynamic> _extendTree({
    required Map<String, dynamic> tree,
    required int depth,
    required int branchingFactor,
    required String currentInput,
  }) {
    final result = <String, dynamic>{};

    for (final key in tree.keys) {
      final value = tree[key];

      if (value == null) {
        // Terminal node - extend it by adding new children
        if (depth <= 0) {
          result[key] = null;
        } else {
          result[key] = _generateMockSuggestionChildren(
            parent: key,
            currentInput: currentInput,
            depth: depth,
            branchingFactor: branchingFactor,
          );
        }
      } else if (value is Map<String, dynamic>) {
        // Non-terminal node - recursively extend its children
        result[key] = _extendTree(
          tree: value,
          depth: depth,
          branchingFactor: branchingFactor,
          currentInput: currentInput,
        );
      } else {
        // Unknown structure, keep as-is
        result[key] = value;
      }
    }

    return result;
  }

  /// Generate mock suggestion children
  Map<String, dynamic> _generateMockSuggestionChildren({
    required String parent,
    required String currentInput,
    required int depth,
    required int branchingFactor,
  }) {
    // Predefined suggestion patterns based on common Chinese phrases
    final suggestionPatterns = {
      '吃了': ['苹果', '香蕉', '梨', '西瓜', '葡萄', '橙子'],
      '喝了': ['水', '茶', '咖啡', '果汁', '牛奶', '可乐'],
      '心情': ['很好', '很糟', '还可以', '不错', '一般', '糟透了'],
      '想要': ['出去玩', '学习', '上班', '休息', '睡觉', '运动'],
      '去了': ['公园', '商场', '学校', '公司', '医院', '图书馆'],
      '看了': ['电影', '书', '电视', '新闻', '比赛', '展览'],
      '买了': ['衣服', '食物', '书籍', '电子产品', '日用品', '礼物'],
      '见了': ['朋友', '家人', '同事', '老师', '医生', '客户'],
    };

    final children = suggestionPatterns[parent] ??
        ['选项1', '选项2', '选项3', '选项4', '选项5', '选项6'];

    final result = <String, dynamic>{};
    final count = branchingFactor < children.length
        ? branchingFactor
        : children.length;

    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (depth <= 1) {
        result[child] = null;
      } else {
        // For deeper levels, generate more generic suggestions
        result[child] = _generateGenericSuggestions(
          depth: depth - 1,
          branchingFactor: branchingFactor,
        );
      }
    }

    return result;
  }

  /// Generate generic suggestions for deeper levels
  Map<String, dynamic> _generateGenericSuggestions({
    required int depth,
    required int branchingFactor,
  }) {
    final generic = ['了', '的', '很开心', '很满意', '不太好', '还行'];
    final result = <String, dynamic>{};
    final count = branchingFactor < generic.length
        ? branchingFactor
        : generic.length;

    for (var i = 0; i < count; i++) {
      result[generic[i]] = depth <= 1 ? null : <String, dynamic>{};
    }

    return result;
  }

  /// Send verification code via SMS
  ///
  /// API Design:
  /// POST /api/v1/auth/send-code
  /// Request: {"phone": "+86xxxxxxxxxx"}
  /// Response: {"success": true, "message": "Code sent"}
  Future<void> sendVerificationCode(String phoneNumber) async {
    // TODO: Implement actual API call
    // Mock implementation
    await Future.delayed(const Duration(seconds: 1));

    /* Actual implementation:
    final url = Uri.parse('$baseUrl/api/v1/auth/send-code');
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phoneNumber}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw AutomateBackendException(error['message'] ?? 'Failed to send code');
    }
    */
  }

  /// Verify phone number and code, returns auth token
  ///
  /// API Design:
  /// POST /api/v1/auth/verify
  /// Request: {"phone": "+86xxxxxxxxxx", "code": "123456"}
  /// Response: {
  ///   "success": true,
  ///   "token": "jwt_token_here",
  ///   "user": {
  ///     "id": "user_id",
  ///     "phone": "+86xxxxxxxxxx",
  ///     "is_new_user": true
  ///   }
  /// }
  Future<AuthResponse> verifyCode(String phoneNumber, String code) async {
    // TODO: Implement actual API call
    // Mock implementation
    await Future.delayed(const Duration(seconds: 1));

    return AuthResponse(
      token: 'mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'mock_user_id',
      isNewUser: true,
    );

    /* Actual implementation:
    final url = Uri.parse('$baseUrl/api/v1/auth/verify');
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phoneNumber,
        'code': code,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw AutomateBackendException(error['message'] ?? 'Verification failed');
    }

    final data = jsonDecode(response.body);
    return AuthResponse.fromJson(data);
    */
  }

  /// Mark onboarding as complete
  ///
  /// API Design:
  /// POST /api/v1/user/onboarding/complete
  /// Headers: Authorization: Bearer {token}
  /// Response: {"success": true}
  Future<void> completeOnboarding(String userId) async {
    // TODO: Implement actual API call
    await Future.delayed(const Duration(milliseconds: 500));

    /* Actual implementation:
    final url = Uri.parse('$baseUrl/api/v1/user/onboarding/complete');
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw AutomateBackendException('Failed to complete onboarding');
    }
    */
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Response from authentication API
class AuthResponse {
  final String token;
  final String userId;
  final bool isNewUser;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.isNewUser,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String,
      userId: json['user']['id'] as String,
      isNewUser: json['user']['is_new_user'] as bool,
    );
  }
}

/// Exception thrown by Automate backend
class AutomateBackendException implements Exception {
  final String message;

  AutomateBackendException(this.message);

  @override
  String toString() => 'AutomateBackendException: $message';
}
