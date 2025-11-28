/// The onboarding chatbot page.
/// Loads past messages, streams replies, and auto-completion suggestions.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:automate/automate/backend/backend.dart';
import 'package:provider/provider.dart';
import 'onboarding_chatbot_view.dart';

class OnboardingChatbot extends StatefulWidget {
  const OnboardingChatbot({super.key});

  @override
  OnboardingChatbotController createState() => OnboardingChatbotController();
}

class OnboardingChatbotController extends State<OnboardingChatbot> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final List<ChatMessage> messages = [];
  late AutomateApiClient backend;

  bool isLoading = false;

  // Animation state
  bool isFinishing = false;
  bool showCountdown = false;
  String finishText = '';
  int countdown = 5;

  // Suggestion state - tree at current level
  Map<String, dynamic>? _suggestionTree;
  bool isLoadingSuggestions = false;
  bool isExtendingTree = false;
  List<String> clicksDuringExtension = [];
  String lastInputForSuggestions = '';
  Timer? _suggestionDebounce;
  int _suggestionGeneration = 0;

  Map<String, dynamic>? get suggestionTree => _suggestionTree;
  set suggestionTree(Map<String, dynamic>? value) {
    _suggestionTree = value;

    // Schedule extension check on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) { _checkAndExtendTreeNonRecursive(); });
  }

  List<String> get currentSuggestions {
    if (_suggestionTree == null || _suggestionTree!.isEmpty) return [];
    return _suggestionTree!.keys.toList();
  }

  static const int initialSuggestionDepth = 2;
  static const int suggestionBranchingFactor = 2;
  static const int treeExtensionTriggerDepth = 1;
  static const int maxSuggestionTreeDepth = 2;

  @override
  void initState() {
    super.initState();
    backend = context.read<AutomateApiClient>();
    _initialize();
  }

  Future<void> _initialize() async {
    _sendInitialGreeting();
    try {
      final history = await backend.fetchMessages();
      if (!mounted) return;
      _addMessagesFromHistory(history);
    } on UnauthorizedException {
      // return;
    } catch (_) {}

    messageController.addListener(_onInputChanged);
    if (!mounted) return;
    try {
      await _loadSuggestions();
    } on UnauthorizedException {
      // Auth gate will handle redirect
      // return;
    }
  }

  void _sendInitialGreeting() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    const greeting = '你好！👋 欢迎使用智能助手。\n\n我可以帮你自动完成各种任务。请告诉我，你想让我帮你做什么？\n\n例如：\n• "每天早上 8 点提醒我查看邮件"\n• "帮我整理待办事项"\n• "监控某个网站的价格变动"';

    _addMessage(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: greeting,
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void _addMessage(ChatMessage message) {
    if (!mounted) return;
    setState(() => messages.add(message));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startFinishSequence() async {
    if (!mounted) return;
    setState(() {
      isFinishing = true;
      showCountdown = false;
      finishText = '';
      countdown = 5;
    });

    // 1. Focus/Blur Animation Phase (3s)
    // Wait for the UI to blur and the text to "lift off"
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;

    // 2. Typing Animation Phase
    const fullText = "我将为你招聘一名员工来完成它，需要一些时间...\n\n您先去忙其他事情吧，进度推进后我会通知您。\n\n将于 5 秒后置于后台工作";
    
    // Split by characters but keep newlines as distinct pauses if needed
    // Here we just type character by character but slower
    for (int i = 0; i < fullText.length; i++) {
      if (!mounted) return;
      
      // Variable typing speed for realism
      // Punctuation marks get a slightly longer pause
      final char = fullText[i];
      int delay = 100;
      if (char == '，' || char == '、') delay = 200;
      if (char == '。' || char == '\n') delay = 400;

      await Future.delayed(Duration(milliseconds: delay));
      
      setState(() {
        finishText += char;
      });
    }

    // Brief pause after typing finishes before countdown emphasis
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    
    setState(() {
      showCountdown = true;
    });
    
    // 3. Countdown Phase
    while (countdown > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {
        countdown--;
      });
    }
    
    // Final brief pause at 0
    await Future.delayed(const Duration(milliseconds: 500));

    completeOnboarding();
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (isLoading || text.isEmpty) return;

    _suggestionGeneration++;

    _addMessage(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );

    messageController.clear();
    setState(() => isLoading = true);

    _addMessage(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    // 缓存 delta 内容，等待 decision 事件
    final deltaBuffer = StringBuffer();
    bool? decisionReceived;
    bool shouldStop = false;

    try {
      await for (final event in backend.streamChatResponse(text)) {
        if (!mounted) return;

        switch (event.type) {
          case ChatStreamEventType.delta:
            if (decisionReceived == null) {
              // decision 还没到，先缓存
              deltaBuffer.write(event.content ?? '');
            } else if (!shouldStop) {
              // decision 已到且不停止，直接渲染
              setState(() {
                messages.last.text += event.content ?? '';
              });
              _scrollToBottom();
            }
            // 如果 shouldStop = true，忽略后续 delta
            break;

          case ChatStreamEventType.decision:
            decisionReceived = true;
            shouldStop = event.shouldStop ?? false;

            if (shouldStop) {
              // 丢弃缓存，显示固定消息
              setState(() {
                messages.last.text = '好的，我明白了，正在为您安排...';
              });
              _scrollToBottom();
            } else {
              // 开始渲染缓存的内容
              final buffered = deltaBuffer.toString();
              if (buffered.isNotEmpty) {
                setState(() {
                  messages.last.text = buffered;
                });
                _scrollToBottom();
              }
            }
            break;

          case ChatStreamEventType.assistantMessage:
            // 完整消息到达，如果之前没收到 decision，直接使用完整内容
            if (decisionReceived == null || !shouldStop) {
              setState(() {
                messages.last.text = event.content ?? '';
              });
              _scrollToBottom();
            }
            break;

          case ChatStreamEventType.done:
            // 流结束，如果 shouldStop = true，触发页面跳转
            if (shouldStop) {
              // 延迟一下让用户看到消息
              await Future.delayed(const Duration(milliseconds: 1000));
              if (mounted) {
                 _startFinishSequence();
              }
            }
            break;
        }
      }
    } on UnauthorizedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages.last.text = _errorText(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          if (!shouldStop) {
            _invalidateAndReloadSuggestions();
          }
        });
      }
    }
  }

  void completeOnboarding() {
    if (mounted) {
      context.go('/rooms');
    }
  }

  void _onInputChanged() {
    final currentInput = messageController.text;
    if (currentInput != lastInputForSuggestions) {
      if (mounted) {
        setState(() {
          suggestionTree = null;
          isLoadingSuggestions = true;
          isExtendingTree = false;
          clicksDuringExtension.clear();
        });
      }
    }

    _suggestionDebounce?.cancel();
    _suggestionDebounce = Timer(const Duration(milliseconds: 400), () {
      final debouncedInput = messageController.text;
      if (!mounted) return;
      if (debouncedInput != lastInputForSuggestions) {
        _invalidateAndReloadSuggestions();
      }
    });
  }

  Future<void> _loadSuggestions({
    Map<String, dynamic>? anchoring,
    int? depth,
  }) async {
    if (!mounted) return;
    final requestId = ++_suggestionGeneration;
    setState(() => isLoadingSuggestions = true);

    try {
      final result = await backend.getSuggestions(
        history: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: depth ?? initialSuggestionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring ?? {},
      );

      if (mounted && requestId == _suggestionGeneration) {
        setState(() {
          suggestionTree = result;
          lastInputForSuggestions = messageController.text;
          isLoadingSuggestions = false;
        });
      }
    } on UnauthorizedException {
      return;
    } catch (_) {
      if (mounted && requestId == _suggestionGeneration) {
        setState(() => isLoadingSuggestions = false);
      }
    }
  }

  Future<void> _invalidateAndReloadSuggestions() async {
    setState(() {
      suggestionTree = null;
      isLoadingSuggestions = true;
    });
    await _loadSuggestions();
  }

  void onSuggestionClick(String suggestion) {
    final newText = messageController.text + suggestion;
    lastInputForSuggestions = newText;
    messageController.text = newText;

    clicksDuringExtension.add(suggestion);

    if (!mounted) return;
    setState(() {
      if (_suggestionTree != null && _suggestionTree!.containsKey(suggestion)) {
        final subtree = _suggestionTree![suggestion];
        suggestionTree = subtree is Map<String, dynamic> ? subtree : null;
      } else {
        suggestionTree = null;
      }
    });
  }

  int _countDepth(dynamic node) {
    if (node == null) return 0;
    if (node is! Map<String, dynamic>) return 0;
    if (node.isEmpty) return 0;

    var maxDepth = 0;
    for (final value in node.values) {
      final childDepth = _countDepth(value);
      if (childDepth > maxDepth) {
        maxDepth = childDepth;
      }
    }
    return 1 + maxDepth;
  }

  void _checkAndExtendTreeNonRecursive() {
    final remainingDepth = _countDepth(_suggestionTree);
    if (remainingDepth <= treeExtensionTriggerDepth && !isLoadingSuggestions && !isExtendingTree) {
      if (_suggestionTree == null || _suggestionTree!.isEmpty) {
        _loadSuggestions();
      } else {
        _extendTree();
      }
    }
  }

  Future<void> _extendTree() async {
    if (isExtendingTree) return;
    final requestId = ++_suggestionGeneration;
    isExtendingTree = true;
    clicksDuringExtension.clear();

    try {
      if (suggestionTree == null || suggestionTree!.isEmpty) {
        isExtendingTree = false;
        return;
      }

      final anchoring = Map<String, dynamic>.from(suggestionTree!);

      final result = await backend.getSuggestions(
        history: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: maxSuggestionTreeDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring,
      );

      var extendedTree = result;
      for (final click in clicksDuringExtension) {
        if (extendedTree.containsKey(click)) {
          final subtree = extendedTree[click];
          extendedTree = subtree is Map<String, dynamic> ? subtree : <String, dynamic>{};
        } else {
          extendedTree = <String, dynamic>{};
          break;
        }
      }

      if (mounted && requestId == _suggestionGeneration) {
        setState(() {
          suggestionTree = extendedTree.isNotEmpty ? extendedTree : null;
          clicksDuringExtension.clear();
          isExtendingTree = false;
        });
      }
    } on UnauthorizedException {
      return;
    } catch (_) {
      if (mounted && requestId == _suggestionGeneration) {
        setState(() {
          clicksDuringExtension.clear();
          isExtendingTree = false;
        });
      }
    } finally {
      isExtendingTree = false;
    }
  }

  List<Map<String, String>> _getPreviousMessages() {
    return messages
        .map((msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.text,
            })
        .toList();
  }

  void _addMessagesFromHistory(List<Map<String, String>> history) {
    if (!mounted) return;
    setState(() {
      messages.addAll(history.map(_fromBackendMessage));
    });
    _scrollToBottom();
  }

  ChatMessage _fromBackendMessage(Map<String, String> msg) {
    final role = msg['role']?.toUpperCase() ?? '';
    final content = msg['content'] ?? '';
    final isUser = role != 'ASSISTANT';
    return ChatMessage(
      id: '${role}_${content.hashCode}_${messages.length}',
      text: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    );
  }

  @override
  void dispose() {
    messageController.removeListener(_onInputChanged);
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String _errorText(Object error) {
    if (error is AutomateBackendException) {
      return error.message;
    }
    return '抱歉，出现了一些问题：${error.toString()}';
  }

  @override
  Widget build(BuildContext context) => OnboardingChatbotView(this);
}

class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
