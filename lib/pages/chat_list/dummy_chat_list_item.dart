import 'package:flutter/material.dart';

class DummyChatListItem extends StatefulWidget {
  final double opacity;
  final bool animate;

  const DummyChatListItem({
    required this.opacity,
    required this.animate,
    super.key,
  });

  @override
  State<DummyChatListItem> createState() => _DummyChatListItemState();
}

class _DummyChatListItemState extends State<DummyChatListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!widget.animate) {
      // 静态模式：保持原来的简单样式
      final titleColor = theme.textTheme.bodyLarge!.color!.withAlpha(100);
      final subtitleColor = theme.textTheme.bodyLarge!.color!.withAlpha(50);
      return Opacity(
        opacity: widget.opacity,
        child: ListTile(
          leading: CircleAvatar(backgroundColor: titleColor),
          title: Row(
            children: [
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: titleColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
          subtitle: Container(
            decoration: BoxDecoration(
              color: subtitleColor,
              borderRadius: BorderRadius.circular(3),
            ),
            height: 12,
            margin: const EdgeInsets.only(right: 22),
          ),
        ),
      );
    }

    // 动画模式：带 shimmer 效果
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final shimmerColor = isDark
            ? Colors.white.withAlpha((30 * _animation.value).toInt())
            : Colors.white.withAlpha((100 * _animation.value).toInt());

        final baseColor = theme.colorScheme.surfaceContainerHigh;
        final highlightColor = theme.colorScheme.surfaceContainer;

        return Opacity(
          opacity: widget.opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // 背景
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // 头像骨架
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: baseColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 内容骨架
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 标题行
                              Row(
                                children: [
                                  Container(
                                    height: 14,
                                    width: 100,
                                    decoration: BoxDecoration(
                                      color: baseColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    height: 12,
                                    width: 40,
                                    decoration: BoxDecoration(
                                      color: highlightColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 副标题
                              Container(
                                height: 12,
                                width: 160,
                                decoration: BoxDecoration(
                                  color: highlightColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Shimmer 闪光效果
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment(-1.0 + 2.5 * _animation.value, -0.3),
                        end: Alignment(-0.3 + 2.5 * _animation.value, 0.3),
                        colors: [
                          Colors.transparent,
                          shimmerColor,
                          shimmerColor.withAlpha(
                            ((shimmerColor.a * 0.6).round()).clamp(0, 255),
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 0.65, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.srcATop,
                      child: Container(
                        color: theme.colorScheme.surfaceContainerLow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
