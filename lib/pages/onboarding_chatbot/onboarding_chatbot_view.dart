import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'chatbot_message_renderer.dart';
import 'onboarding_chatbot.dart';

class OnboardingChatbotView extends StatelessWidget {
  final OnboardingChatbotController controller;

  const OnboardingChatbotView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEDEDED);

    return Scaffold(
      backgroundColor: backgroundColor,
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
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
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
                      padding: const EdgeInsets.only(left: 12, bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ),
                    ),

                  // "开始吧!" 按钮 - 用户发送 >= 3 条消息后显示
                  _StartButton(controller: controller, theme: theme),

                  // 快速开始卡片 - 只在只有欢迎消息时显示
                  if (controller.messages.length == 1 && controller.messages.first.isGreeting)
                    _QuickStartButtons(
                      controller: controller,
                      theme: theme,
                    ),

                  // Suggestion Bubbles - 暂时注释
                  // _SuggestionBubbles(
                  //   controller: controller,
                  //   theme: theme,
                  //   textTheme: textTheme,
                  // ),

                  // Input Area - 使用 mt-auto 效果，自动推到底部
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
    // Greeting 消息用特殊卡片渲染
    if (message.isGreeting) {
      return _GreetingCard(message: message, theme: theme, textTheme: textTheme);
    }

    final isUser = message.isUser;
    final isDark = theme.brightness == Brightness.dark;
    // Brand Colors - 适配深浅色主题
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : (isDark ? const Color(0xFF2A2A2A) : Colors.white);
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : (isDark ? Colors.white : Colors.black);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AI Avatar (Simple Square) - 适配深浅色主题
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(
                  image: AssetImage(isDark ? 'assets/logo_dark.png' : 'assets/logo.png'),
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

/// 欢迎卡片 - 特殊渲染 greeting 消息
class _GreetingCard extends StatelessWidget {
  final ChatMessage message;
  final ThemeData theme;
  final TextTheme textTheme;

  const _GreetingCard({
    required this.message,
    required this.theme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;

    // 解析消息：第一段是标题，其余是内容
    final paragraphs = message.text.split('\n\n');
    final title = paragraphs.isNotEmpty ? paragraphs[0] : '';
    final bodyParagraphs = paragraphs.length > 1 ? paragraphs.sublist(1) : <String>[];

    // 深浅色主题颜色
    final cardBgColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final titleTextColor = isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;
    final bodyTextColor = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardBgColor,
              theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.15 : 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo + 标题行
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A3A3A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        isDark ? 'assets/logo_dark.png' : 'assets/logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: titleTextColor,
                            height: 1.3,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (bodyParagraphs.isNotEmpty) ...[
                const SizedBox(height: 16),
                // 分隔线
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                        theme.colorScheme.primary.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 内容段落
                ChatbotMessageRenderer(
                  text: bodyParagraphs.join('\n\n'),
                  textColor: bodyTextColor,
                  fontSize: 14,
                  linkStyle: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 快速开始任务数据
class _QuickTask {
  final int? id;
  final String label;
  final String description;
  final String defaultMessage;
  final String previewImage; // 预览图片 URL

  const _QuickTask({
    this.id,
    required this.label,
    required this.description,
    required this.defaultMessage,
    required this.previewImage,
  });

  /// 从 API JSON 创建
  factory _QuickTask.fromJson(Map<String, dynamic> json) {
    return _QuickTask(
      id: json['id'] as int?,
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      defaultMessage: json['defaultMessage'] as String? ?? '',
      previewImage: json['previewImage'] as String? ?? '',
    );
  }
}

/// 快速开始按钮组 - 自适应布局（移动端 PageView，PC端 GridView）
class _QuickStartButtons extends StatefulWidget {
  final OnboardingChatbotController controller;
  final ThemeData theme;

  const _QuickStartButtons({
    required this.controller,
    required this.theme,
  });

  @override
  State<_QuickStartButtons> createState() => _QuickStartButtonsState();
}

class _QuickStartButtonsState extends State<_QuickStartButtons> {
  PageController? _pageController;
  int _currentPage = 0;
  bool? _lastIsDesktop;

  /// PC端宽度阈值
  static const double _desktopBreakpoint = 600;

  /// 卡片数据
  List<_QuickTask> _quickTasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuickStartCards();
  }

  Future<void> _loadQuickStartCards() async {
    try {
      final cards = await widget.controller.backend.getQuickStartCards();
      if (mounted) {
        setState(() {
          _quickTasks = cards.map((json) => _QuickTask.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[QuickStartCards] Failed to load: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onPageChanged);
    _pageController?.dispose();
    super.dispose();
  }

  void _initPageController(bool isDesktop) {
    if (_lastIsDesktop == isDesktop && _pageController != null) return;

    _pageController?.removeListener(_onPageChanged);
    _pageController?.dispose();

    // PC端不露出下一页，移动端露出一点
    final viewportFraction = isDesktop ? 1.0 : 0.92;
    _pageController = PageController(viewportFraction: viewportFraction);
    _pageController!.addListener(_onPageChanged);
    _lastIsDesktop = isDesktop;
  }

  void _onPageChanged() {
    final page = _pageController?.page?.round() ?? 0;
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
  }

  /// 处理鼠标滚轮事件
  void _handlePointerSignal(PointerSignalEvent event, int maxPage) {
    if (event is PointerScrollEvent) {
      // 滚轮向下滚动 -> 下一页，向上滚动 -> 上一页
      if (event.scrollDelta.dy > 0) {
        _nextPage(maxPage);
      } else if (event.scrollDelta.dy < 0) {
        _previousPage();
      }
    }
  }

  void _nextPage(int maxPage) {
    if (_currentPage < maxPage - 1) {
      _pageController?.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController?.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 加载中或无数据时不显示
    if (_isLoading || _quickTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= _desktopBreakpoint;

    // 初始化/更新 PageController
    _initPageController(isDesktop);

    if (isDesktop) {
      return _buildDesktopLayout(screenWidth);
    } else {
      return _buildMobileLayout(screenWidth);
    }
  }

  /// PC端布局 - 固定宽度卡片，横向滚动列表，鼠标滚轮连续滚动
  Widget _buildDesktopLayout(double screenWidth) {
    const cardWidth = 480.0;  // 卡片固定宽度
    const cardGap = 16.0;  // 卡片之间间隔
    const horizontalPadding = 32.0;  // 左右边距

    final scrollController = ScrollController();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            // 鼠标滚轮横向滚动，速度加倍
            scrollController.animateTo(
              (scrollController.offset + event.scrollDelta.dy * 3).clamp(
                0.0,
                scrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        },
        child: SizedBox(
          height: 100,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            itemCount: _quickTasks.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  right: index < _quickTasks.length - 1 ? cardGap : 0,
                ),
                child: SizedBox(
                  width: cardWidth,
                  child: _QuickTaskCard(
                    task: _quickTasks[index],
                    theme: widget.theme,
                    controller: widget.controller,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 移动端布局 - 单卡片滑动（保持原样）
  Widget _buildMobileLayout(double screenWidth) {
    final sideMargin = screenWidth * 0.04;
    const cardGap = 6.0;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: SizedBox(
        height: 100,
        child: PageView.builder(
          controller: _pageController,
          itemCount: _quickTasks.length,
          itemBuilder: (context, index) {
            final isFirst = index == 0;
            final isLast = index == _quickTasks.length - 1;
            return Padding(
              padding: EdgeInsets.only(
                left: isFirst ? (sideMargin * 0.3) : cardGap,
                right: isLast ? (sideMargin * 0.3) : cardGap,
              ),
              child: _QuickTaskCard(
                task: _quickTasks[index],
                theme: widget.theme,
                controller: widget.controller,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 快速开始卡片 - 长条形，左图右文
class _QuickTaskCard extends StatelessWidget {
  final _QuickTask task;
  final ThemeData theme;
  final OnboardingChatbotController controller;

  const _QuickTaskCard({
    required this.task,
    required this.theme,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;
    final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(18),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: () => _showTaskDetailDialog(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // 左侧预览图 - 撑满卡片高度
              Container(
                width: 90,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildPreviewImage(task.previewImage, isDark),
                ),
              ),
              const SizedBox(width: 14),
              // 右侧文字内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 标题
                    Text(
                      task.label,
                      style: TextStyle(
                        fontSize: 15,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // 描述/默认消息
                    Text(
                      task.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建预览图（支持本地 assets 和网络 URL）
  Widget _buildPreviewImage(String imageUrl, bool isDark) {
    final isNetworkImage = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetworkImage) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(isDark),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildImagePlaceholder(isDark);
        },
      );
    } else {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(isDark),
      );
    }
  }

  /// 图片占位符
  Widget _buildImagePlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        color: isDark ? Colors.white38 : Colors.grey.shade400,
        size: 32,
      ),
    );
  }

  void _showTaskDetailDialog(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 600;

    if (isDesktop) {
      // PC端使用居中弹窗，保持固定宽度480，高度自适应内容
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _QuickTaskDetailSheet(
              task: task,
              theme: theme,
              isDialog: true,
              onConfirm: (message) {
                Navigator.of(context).pop();
                controller.messageController.text = message;
                controller.sendMessage(isQuickStart: true);
              },
            ),
          ),
        ),
      );
    } else {
      // 移动端使用底部弹窗
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _QuickTaskDetailSheet(
          task: task,
          theme: theme,
          onConfirm: (message) {
            Navigator.of(context).pop();
            controller.messageController.text = message;
            controller.sendMessage(isQuickStart: true);
          },
        ),
      );
    }
  }
}

/// 快速开始详情弹窗（支持底部弹窗和居中对话框两种模式）
class _QuickTaskDetailSheet extends StatefulWidget {
  final _QuickTask task;
  final ThemeData theme;
  final void Function(String message) onConfirm;
  final bool isDialog;

  const _QuickTaskDetailSheet({
    required this.task,
    required this.theme,
    required this.onConfirm,
    this.isDialog = false,
  });

  @override
  State<_QuickTaskDetailSheet> createState() => _QuickTaskDetailSheetState();
}

class _QuickTaskDetailSheetState extends State<_QuickTaskDetailSheet> {
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.task.defaultMessage);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final cardBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖动指示条（仅底部弹窗模式显示）
              if (!widget.isDialog)
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: subtitleColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (!widget.isDialog) const SizedBox(height: 20),

                // 预览图 - 比例与卡片一致 (90:80 = 9:8)
              AspectRatio(
                aspectRatio: 90 / 80,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildDetailPreviewImage(widget.task.previewImage, isDark),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 标题
              Text(
                widget.task.label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),

              // 描述
              Text(
                widget.task.description,
                style: TextStyle(
                  fontSize: 14,
                  color: subtitleColor,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),

              // 可编辑消息区 - 直接显示输入框，带闪动光标
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_note,
                            size: 16,
                            color: widget.theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '编辑发送内容',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                      child: TextField(
                        controller: _editController,
                        maxLines: 4,
                        minLines: 2,
                        style: TextStyle(
                          fontSize: 15,
                          color: textColor,
                          height: 1.4,
                        ),
                        cursorColor: widget.theme.colorScheme.primary,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '点击编辑发送内容...',
                          hintStyle: TextStyle(
                            color: subtitleColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 按钮行
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: subtitleColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final message = _editController.text.trim();
                        if (message.isNotEmpty) {
                          widget.onConfirm(message);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.colorScheme.primary,
                        foregroundColor: widget.theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, size: 18),
                          SizedBox(width: 8),
                          Text(
                            '发送',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建详情页预览图（支持本地 assets 和网络 URL）
  Widget _buildDetailPreviewImage(String imageUrl, bool isDark) {
    final isNetworkImage = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetworkImage) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _buildDetailImagePlaceholder(isDark),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildDetailImagePlaceholder(isDark);
        },
      );
    } else {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _buildDetailImagePlaceholder(isDark),
      );
    }
  }

  /// 详情页图片占位符
  Widget _buildDetailImagePlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        color: isDark ? Colors.white38 : Colors.grey.shade400,
        size: 48,
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
    final isDark = widget.theme.brightness == Brightness.dark;
    final inputBarColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF7F7F7);
    final inputFieldColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final inputTextColor = isDark ? Colors.white : Colors.black;

    return Container(
      color: inputBarColor,
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
                  color: inputFieldColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Focus(
                  onKeyEvent: (node, event) {
                    // PC端：回车发送，Shift+回车换行
                    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter;
                    if (PlatformInfos.isDesktop &&
                        event is KeyDownEvent &&
                        isEnter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      if (!widget.controller.isLoading &&
                          widget.controller.messageController.text.trim().isNotEmpty) {
                        widget.controller.sendMessage();
                      }
                      return KeyEventResult.handled; // 阻止换行
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.controller.messageController,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(fontSize: 16, color: inputTextColor),
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

/// "开始吧!" 按钮 - 用户发送 >= 3 条消息后浮现
class _StartButton extends StatefulWidget {
  final OnboardingChatbotController controller;
  final ThemeData theme;

  const _StartButton({
    required this.controller,
    required this.theme,
  });

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canManuallyStart) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            );
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  widget.theme.colorScheme.primary,
                  widget.theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.controller.manuallyStartFinish,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.rocket_launch_rounded,
                        color: widget.theme.colorScheme.onPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '开始吧!',
                        style: TextStyle(
                          color: widget.theme.colorScheme.onPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final textColor = isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;

    return Material(
      color: bubbleColor,
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
             border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: textColor,
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

