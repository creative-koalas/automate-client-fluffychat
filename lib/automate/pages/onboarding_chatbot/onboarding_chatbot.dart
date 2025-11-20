/// The onboarding chatbot page.
/// User is automatically redirected to this page after successful signup.
/// This page guides the user to describe their first automation task.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluffychat/automate/backend.dart';
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
  final AutomateBackend backend = AutomateBackend();

  bool isLoading = false;
  bool isStreaming = false;
  StreamSubscription<String>? streamSubscription;

  // Suggestion state - tree at current level
  Map<String, dynamic>? suggestionTree;
  bool isLoadingSuggestions = false;
  bool isExtendingTree = false; // Track background extension
  String lastInputForSuggestions = '';

  // Derived from tree - no separate state needed
  List<String> get currentSuggestions {
    if (suggestionTree == null || suggestionTree!.isEmpty) return [];
    return suggestionTree!.keys.toList();
  }

  // Suggestion tree parameters
  static const int initialSuggestionDepth = 3; // Initial tree depth (3 levels: 3 + 9 + 27 = 39 nodes)
  static const int suggestionBranchingFactor = 3; // Branching factor
  static const int minRemainingDepth = 1; // Extend when only 1 level remains
  static const int extensionDepth = 2; // Extend by 2 levels each time

  @override
  void initState() {
    super.initState();
    _sendInitialGreeting();
    messageController.addListener(_onInputChanged);
    _loadInitialSuggestions();
  }

  void _sendInitialGreeting() async {
    setState(() => isLoading = true);

    // Simulate slight delay for natural feel
    await Future.delayed(const Duration(milliseconds: 500));

    // Add AI greeting message with streaming effect
    _addMessage(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    final greeting = '你好！👋 欢迎使用智能助手。\n\n我可以帮你自动完成各种任务。请告诉我，你想让我帮你做什么？\n\n例如：\n• "每天早上 8 点提醒我查看邮件"\n• "帮我整理待办事项"\n• "监控某个网站的价格变动"';

    await _streamTextToLastMessage(greeting);

    setState(() => isLoading = false);
  }

  Future<void> _streamTextToLastMessage(String fullText) async {
    setState(() => isStreaming = true);

    final chars = fullText.characters.toList();
    for (int i = 0; i < chars.length; i++) {
      await Future.delayed(const Duration(milliseconds: 15));
      if (mounted) {
        setState(() {
          messages.last.text += chars[i];
        });
        _scrollToBottom();
      }
    }

    setState(() => isStreaming = false);
  }

  void _addMessage(ChatMessage message) {
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

  Future<void> sendMessage() async {
    final text = messageController.text;
    if (isLoading || isStreaming) return;

    // Add user message
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

    // Add placeholder for AI response
    _addMessage(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    try {
      // Stream the AI response
      await for (final chunk in backend.streamChatResponse(text)) {
        if (mounted) {
          setState(() {
            messages.last.text += chunk;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Handle error
      setState(() {
        messages.last.text = '抱歉，出现了一些问题。请稍后再试。';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  void completeOnboarding() {
    // TODO: Mark onboarding as complete and navigate to main app
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/rooms');
    }
  }

  // Suggestion methods

  void _onInputChanged() {
    final currentInput = messageController.text;

    // If input changed by user (not by suggestion click), invalidate suggestions
    if (currentInput != lastInputForSuggestions) {
      _invalidateAndReloadSuggestions();
    }
  }

  Future<void> _loadInitialSuggestions() async {
    setState(() => isLoadingSuggestions = true);

    try {
      final anchoring = {
        '我想': null,
        '我要': null,
        '帮我': null,
      };

      final result = await backend.getSuggestions(
        previousMessages: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: initialSuggestionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring,
      );

      if (mounted) {
        setState(() {
          suggestionTree = result;
          lastInputForSuggestions = messageController.text;
          isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingSuggestions = false);
      }
    }
  }

  Future<void> _invalidateAndReloadSuggestions() async {
    // Clear current suggestions
    setState(() {
      suggestionTree = null;
      isLoadingSuggestions = true;
    });

    // Reload with new input
    try {
      final anchoring = {
        '我想': null,
        '我要': null,
        '帮我': null,
      };

      final result = await backend.getSuggestions(
        previousMessages: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: initialSuggestionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring,
      );

      if (mounted) {
        setState(() {
          suggestionTree = result;
          lastInputForSuggestions = messageController.text;
          isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingSuggestions = false);
      }
    }
  }

  void onSuggestionClick(String suggestion) {
    // Add suggestion to input
    final newText = messageController.text + suggestion;

    // Update lastInputForSuggestions BEFORE changing text to prevent listener from invalidating
    lastInputForSuggestions = newText;
    messageController.text = newText;

    // Cut the tree - replace with the clicked suggestion's subtree
    setState(() {
      if (suggestionTree != null && suggestionTree!.containsKey(suggestion)) {
        final subtree = suggestionTree![suggestion];
        print('[Click] suggestion=$suggestion, subtree type=${subtree.runtimeType}, keys=${subtree is Map ? (subtree as Map).keys.toList() : 'null'}');
        suggestionTree = subtree is Map<String, dynamic> ? subtree : null;
        print('[Click] new tree keys=${suggestionTree?.keys.toList()}');
      } else {
        print('[Click] suggestion=$suggestion not found in tree');
        suggestionTree = null;
      }
    });

    // Check if we need to extend the tree
    final depth = _countDepth(suggestionTree);
    print('[Click] remaining depth=$depth');
    _checkAndExtendTree();
  }

  int _countDepth(dynamic node) {
    if (node == null) return 0;
    if (node is! Map<String, dynamic>) return 0;
    if (node.isEmpty) return 0;

    int maxDepth = 0;
    for (final value in node.values) {
      final childDepth = _countDepth(value);
      if (childDepth > maxDepth) {
        maxDepth = childDepth;
      }
    }

    return 1 + maxDepth;
  }

  Future<void> _checkAndExtendTree() async {
    final remainingDepth = _countDepth(suggestionTree);

    if (remainingDepth <= minRemainingDepth && !isLoadingSuggestions && !isExtendingTree) {
      await _extendTree();
    }
  }

  Future<void> _extendTree() async {
    // Set flag to prevent overlapping extensions
    if (isExtendingTree) return;
    isExtendingTree = true;

    // Don't set isLoadingSuggestions = true here, load in background
    // Keep showing cached suggestions while extending

    try {
      if (suggestionTree == null || suggestionTree!.isEmpty) {
        isExtendingTree = false;
        return;
      }

      // Build anchoring suggestions from current tree
      final anchoring = <String, dynamic>{};
      for (final key in suggestionTree!.keys) {
        anchoring[key] = suggestionTree![key];
      }

      // Request extension (extend by extensionDepth levels)
      final result = await backend.getSuggestions(
        previousMessages: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: extensionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring,
      );

      // Replace tree with extended version
      if (mounted) {
        setState(() {
          suggestionTree = result;
          isExtendingTree = false;
        });
      }
    } catch (e) {
      // Silently fail, keep showing cached suggestions
      if (mounted) {
        setState(() {
          isExtendingTree = false;
        });
      }
    }
  }

  List<Map<String, String>> _getPreviousMessages() {
    return messages.map((msg) {
      return {
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      };
    }).toList();
  }

  @override
  void dispose() {
    messageController.removeListener(_onInputChanged);
    messageController.dispose();
    scrollController.dispose();
    streamSubscription?.cancel();
    super.dispose();
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
