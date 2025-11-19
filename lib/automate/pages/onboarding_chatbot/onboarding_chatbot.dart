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

  @override
  void initState() {
    super.initState();
    _sendInitialGreeting();
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

  @override
  void dispose() {
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
