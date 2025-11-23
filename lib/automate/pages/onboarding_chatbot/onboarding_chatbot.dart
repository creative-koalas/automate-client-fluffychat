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
  Map<String, dynamic>? _suggestionTree;
  bool isLoadingSuggestions = false;
  bool isExtendingTree = false; // Track background extension
  List<String> clicksDuringExtension = []; // Track clicks made during extension
  String lastInputForSuggestions = '';

  // Getter for tree
  Map<String, dynamic>? get suggestionTree => _suggestionTree;

  // Setter that triggers extension check
  set suggestionTree(Map<String, dynamic>? newTree) {
    _suggestionTree = newTree;
    // Schedule extension check on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndExtendTreeNonRecursive();
    });
  }

  // Derived from tree - no separate state needed
  List<String> get currentSuggestions {
    if (_suggestionTree == null || _suggestionTree!.isEmpty) return [];
    return _suggestionTree!.keys.toList();
  }

  // Suggestion tree parameters
  static const int initialSuggestionDepth = 3; // Initial tree depth (3 levels: 3 + 9 + 27 = 39 nodes)
  static const int suggestionBranchingFactor = 3; // Branching factor
  static const int minRemainingDepth = 1; // Extend when only 1 level remains
  static const int extensionDepth = 2; // Extend by 2 levels each time

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _sendInitialGreeting();
    messageController.addListener(_onInputChanged);
    await _loadSuggestions();
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

    const greeting = '你好！👋 欢迎使用智能助手。\n\n我可以帮你自动完成各种任务。请告诉我，你想让我帮你做什么？\n\n例如：\n• "每天早上 8 点提醒我查看邮件"\n• "帮我整理待办事项"\n• "监控某个网站的价格变动"';

    await _streamTextToLastMessage(greeting);

    setState(() => isLoading = false);
  }

  Future<void> _streamTextToLastMessage(String fullText) async {
    setState(() => isStreaming = true);

    final chars = fullText.characters.toList();
    for (var i = 0; i < chars.length; i++) {
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
    final text = messageController.text.trim();
    if (isLoading || isStreaming || text.isEmpty) return;

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
      setState(() {
        messages.last.text = _errorText(e);
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

  /// Load suggestions with optional anchoring
  /// If anchoring is null, backend will use default initial suggestions
  Future<void> _loadSuggestions({
    Map<String, dynamic>? anchoring,
    int? depth,
  }) async {
    setState(() => isLoadingSuggestions = true);

    try {
      final result = await backend.getSuggestions(
        previousMessages: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: depth ?? initialSuggestionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring ?? {},
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
    await _loadSuggestions();
  }

  void onSuggestionClick(String suggestion) {
    // Add suggestion to input
    final newText = messageController.text + suggestion;

    // Update lastInputForSuggestions BEFORE changing text to prevent listener from invalidating
    lastInputForSuggestions = newText;
    messageController.text = newText;

    // Track click if extension is in progress
    if (isExtendingTree) {
      clicksDuringExtension.add(suggestion);
    }

    // Cut the tree - replace with the clicked suggestion's subtree
    setState(() {
      if (_suggestionTree != null && _suggestionTree!.containsKey(suggestion)) {
        final subtree = _suggestionTree![suggestion];
        suggestionTree = subtree is Map<String, dynamic> ? subtree : null;
      } else {
        suggestionTree = null;
      }
    });
    // Setter will automatically trigger extension check if needed
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

  // Non-recursive version that doesn't await - just starts the process
  void _checkAndExtendTreeNonRecursive() {
    final remainingDepth = _countDepth(_suggestionTree);

    if (remainingDepth <= minRemainingDepth && !isLoadingSuggestions && !isExtendingTree) {
      // If tree is null/empty, reload from scratch instead of extending
      if (_suggestionTree == null || _suggestionTree!.isEmpty) {
        _loadSuggestions();
      } else {
        _extendTree();
      }
    }
  }


  Future<void> _extendTree() async {
    // Set flag to prevent overlapping extensions
    if (isExtendingTree) return;
    isExtendingTree = true;
    clicksDuringExtension.clear();

    // Don't set isLoadingSuggestions = true here, load in background
    // Keep showing cached suggestions while extending

    try {
      if (suggestionTree == null || suggestionTree!.isEmpty) {
        isExtendingTree = false;
        return;
      }

      // Pass the entire current tree as anchoring (not just keys!)
      final anchoring = Map<String, dynamic>.from(suggestionTree!);


      // Request extension (extend by extensionDepth levels)
      final result = await backend.getSuggestions(
        previousMessages: _getPreviousMessages(),
        currentInput: messageController.text,
        depth: extensionDepth,
        branchingFactor: suggestionBranchingFactor,
        anchoringSuggestions: anchoring,
      );

      // Apply clicks that happened during extension
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

      // Replace tree with extended version (with clicks applied)
      if (mounted) {
        setState(() {
          suggestionTree = extendedTree.isNotEmpty ? extendedTree : null;
          clicksDuringExtension.clear();
          isExtendingTree = false;
        });
        // Setter will automatically trigger extension check if needed
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          clicksDuringExtension.clear();
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
