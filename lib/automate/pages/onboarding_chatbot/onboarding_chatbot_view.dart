import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:automate/config/themes.dart';
import 'chatbot_message_renderer.dart';
import 'onboarding_chatbot.dart';

class OnboardingChatbotView extends StatelessWidget {
  final OnboardingChatbotController controller;

  const OnboardingChatbotView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    const backgroundColor = Color(0xFFEDEDED);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: controller.isFinishing
          ? null
          : AppBar(
              backgroundColor: backgroundColor,
              elevation: 0,
              centerTitle: true,
              title: const Text('Automate',
                  style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 17)),
              automaticallyImplyLeading: false,
            ),
      body: Stack(
        children: [
          AnimatedOpacity(
            opacity: controller.isFinishing ? 0.0 : 1.0,
            duration: const Duration(seconds: 2),
            curve: Curves.easeOut,
            child: SafeArea(
              child: Column(
                children: [
                  // Messages List
                  Expanded(
                    child: ListView.builder(
                      controller: controller.scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      itemCount: controller.messages.length,
                      itemBuilder: (context, index) {
                        final message = controller.messages[index];
                        return _MessageBubble(
                          message: message,
                          theme: theme,
                          textTheme: textTheme,
                        );
                      },
                    ),
                  ),

                  // Loading Indicator (Simple text or small spinner)
                  if (controller.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ),
                    ),

                  // Suggestion Bubbles
                  _SuggestionBubbles(
                    controller: controller,
                    theme: theme,
                    textTheme: textTheme,
                  ),

                  // Input Area
                  _InputArea(
                    controller: controller,
                    theme: theme,
                    textTheme: textTheme,
                  ),
                ],
              ),
            ),
          ),
          
          if (controller.isFinishing)
            _FinishingOverlay(
              controller: controller,
              theme: theme,
              textTheme: textTheme,
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ThemeData theme;
  final TextTheme textTheme;

  const _MessageBubble({
    required this.message,
    required this.theme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    // Brand Colors (Avoid WeChat Green)
    final bubbleColor = isUser ? theme.colorScheme.primary : Colors.white;
    final textColor = isUser ? theme.colorScheme.onPrimary : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AI Avatar (Simple Square)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                image: const DecorationImage(
                  image: AssetImage('assets/logo.png'), 
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          // Message Content
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(6), // Standard rounded corners
              ),
              child: ChatbotMessageRenderer(
                text: message.text.isEmpty ? ' ' : message.text,
                textColor: textColor,
                isUser: isUser,
                linkStyle: TextStyle(
                  color: isUser ? Colors.white : theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: isUser ? Colors.white : theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
             // User Avatar - Brand Style
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 40, 
                height: 40,
                color: theme.colorScheme.primaryContainer, // Theme color
                child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer, size: 28),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final delay = index * 0.2;
              final value = (_controller.value - delay) % 1.0;
              final opacity = value < 0.5 ? (value * 2) : (2 - value * 2);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: opacity.clamp(0.3, 1.0)),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _InputArea extends StatefulWidget {
  final OnboardingChatbotController controller;
  final ThemeData theme;
  final TextTheme textTheme;

  const _InputArea({
    required this.controller,
    required this.theme,
    required this.textTheme,
  });

  @override
  State<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<_InputArea> {
  bool hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.messageController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newHasText = widget.controller.messageController.text.isNotEmpty;
    if (newHasText != hasText) {
      setState(() {
        hasText = newHasText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // WeChat Input Area Style
    return Container(
      color: const Color(0xFFF7F7F7), // Light gray background for input bar
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left Padding for balance
            const SizedBox(width: 4),
            
            // Text Input
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 120,
                  minHeight: 40,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextField(
                  controller: widget.controller.messageController,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  enabled: !widget.controller.isLoading,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => widget.controller.sendMessage(),
                ),
              ),
            ),
            
            // Send Button
            if (hasText) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4), // (40px - 32px) / 2 = 4px centering
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.colorScheme.primary, // Brand Color
                    foregroundColor: widget.theme.colorScheme.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(50, 32), // Compact size
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), // Pill shape
                    ),
                  ),
                  onPressed: widget.controller.isLoading ? null : widget.controller.sendMessage,
                  child: const Text('发送', style: TextStyle(fontSize: 14)), 
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionBubbles extends StatelessWidget {
  final OnboardingChatbotController controller;
  final ThemeData theme;
  final TextTheme textTheme;

  const _SuggestionBubbles({
    required this.controller,
    required this.theme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show suggestions while AI is responding
    if (controller.isLoading) {
      return const SizedBox.shrink();
    }

    // Show loading skeleton when loading or extending with no suggestions
    if (controller.isLoadingSuggestions ||
        (controller.isExtendingTree && controller.currentSuggestions.isEmpty)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(3, (index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SkeletonBubble(theme: theme),
              );
            }),
          ),
        ),
      );
    }

    // Show actual suggestions
    if (controller.currentSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: controller.currentSuggestions.asMap().entries.map((entry) {
            final index = entry.key;
            final suggestion = entry.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SuggestionBubble(
                text: suggestion,
                index: index,
                onTap: () => controller.onSuggestionClick(suggestion),
                theme: theme,
                textTheme: textTheme,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SuggestionBubble extends StatelessWidget {
  final String text;
  final int index;
  final VoidCallback onTap;
  final ThemeData theme;
  final TextTheme textTheme;

  const _SuggestionBubble({
    required this.text,
    required this.index,
    required this.onTap,
    required this.theme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18), // Pill shape
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minWidth: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
             borderRadius: BorderRadius.circular(18),
             border: Border.all(color: Colors.grey[300]!),
          ),
          child: Center(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBubble extends StatefulWidget {
  final ThemeData theme;

  const _SkeletonBubble({required this.theme});

  @override
  State<_SkeletonBubble> createState() => _SkeletonBubbleState();
}

class _SkeletonBubbleState extends State<_SkeletonBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.5, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          constraints: const BoxConstraints(minWidth: 100),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: _animation.value),
            borderRadius: BorderRadius.circular(24),
          ),
        );
      },
    );
  }
}

class _FinishingOverlay extends StatefulWidget {
  final OnboardingChatbotController controller;
  final ThemeData theme;
  final TextTheme textTheme;

  const _FinishingOverlay({
    required this.controller,
    required this.theme,
    required this.textTheme,
  });

  @override
  State<_FinishingOverlay> createState() => _FinishingOverlayState();
}

class _FinishingOverlayState extends State<_FinishingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _glowController;
  
  late Animation<double> _backgroundOpacity;
  late Animation<double> _blurSigma;
  late Animation<double> _textMoveY;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Controller for the entry sequence (Background fade in + Text move up)
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // Slower: 3 seconds
    );

    // 1. Background Opacity: Gradual darken
    _backgroundOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
      ),
    );

    // 2. Blur Intensity: Gradual blur
    _blurSigma = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
      ),
    );

    // 3. Text Movement: From bottom (approx message location) to center
    // Using a large offset to simulate coming from the bottom of the screen
    _textMoveY = Tween<double>(begin: 300.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        // Start slightly later to let blur settle in a bit? No, synchronous is better for "lifting"
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic), 
      ),
    );

    // Continuous glow animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Start entry animation immediately
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastMessage = widget.controller.messages.isNotEmpty 
        ? widget.controller.messages.last.text 
        : '';
        
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        return Stack(
          children: [
            // 1. Blur Background (Glassmorphism)
            // We animate the sigma and the color opacity
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _blurSigma.value,
                sigmaY: _blurSigma.value,
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.6 * _backgroundOpacity.value),
              ),
            ),
            
            // 2. Radial Gradient Overlay for Focus
            Opacity(
              opacity: _backgroundOpacity.value,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      widget.theme.colorScheme.primary.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // Animated Main Text
                  // Driven by _entryController for movement
                  Transform.translate(
                    offset: Offset(0, _textMoveY.value),
                    child: Transform.scale(
                      // Subtle scale up as it reaches center
                      scale: 1.0 + (1.0 - (_textMoveY.value / 300.0).clamp(0.0, 1.0)) * 0.1,
                      child: AnimatedBuilder(
                        animation: _glowAnimation,
                        builder: (context, child) {
                          // Only show glow/shadow fully when near center to avoid distraction during move
                          final entryProgress = _entryController.value;
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              lastMessage,
                              textAlign: TextAlign.center,
                              style: widget.textTheme.headlineSmall?.copyWith(
                                color: Colors.white.withValues(
                                  // Fade text in slightly if we want, or keep it solid (it's "moving" from the list)
                                  // Keeping it solid is better for the "extraction" illusion
                                  alpha: 1.0 
                                ),
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                                letterSpacing: 0.5,
                                shadows: [
                                  BoxShadow(
                                    color: widget.theme.colorScheme.primary.withValues(
                                      alpha: 0.6 * entryProgress // Glow fades in as it centers
                                    ),
                                    blurRadius: 25 * _glowAnimation.value,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: Colors.black45,
                                    offset: const Offset(0, 4),
                                    blurRadius: 8 * entryProgress,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  const Spacer(flex: 2),
                  
                  // Streamed Secondary Text (Typewriter style)
                  Container(
                    constraints: const BoxConstraints(minHeight: 100),
                    alignment: Alignment.topCenter,
                    child: widget.controller.finishText.isNotEmpty
                      ? AnimatedOpacity(
                          duration: const Duration(milliseconds: 500),
                          opacity: 1.0,
                          child: Text(
                            widget.controller.finishText,
                            textAlign: TextAlign.center,
                            style: widget.textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.6,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 20),
                  
                  // Progress/Countdown Indicator
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 800),
                    opacity: widget.controller.showCountdown ? 1.0 : 0.0,
                    child: Column(
                      children: [
                         SizedBox(
                          width: 48,
                          height: 48,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: widget.controller.countdown / 5.0,
                                strokeWidth: 3,
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.theme.colorScheme.primary,
                                ),
                              ),
                              Text(
                                '${widget.controller.countdown}',
                                style: widget.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '正在安排后台任务...',
                          style: widget.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

