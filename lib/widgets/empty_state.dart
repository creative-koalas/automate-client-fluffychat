import 'package:flutter/material.dart';

/// 空状态组件
/// 用于列表为空时显示友好的提示
/// 带有入场动画效果
class EmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconBounceAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // 图标缩放动画
    _iconScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    // 图标弹跳动画（循环）
    _iconBounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    // 文字淡入动画
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    // 文字滑入动画
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标 - 带动画
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // 小幅度上下浮动效果
                final bounceOffset = _iconBounceAnimation.value * 8;
                return Transform.translate(
                  offset: Offset(0, -bounceOffset + 4),
                  child: Transform.scale(
                    scale: _iconScaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: _buildIconContainer(theme),
            ),
            const SizedBox(height: 24),

            // 文字内容 - 带动画
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    // 标题
                    Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // 副标题
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    // 操作按钮
                    if (widget.actionLabel != null && widget.onAction != null) ...[
                      const SizedBox(height: 24),
                      _buildActionButton(theme),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconContainer(ThemeData theme) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.1),
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.08),
          ],
        ),
        boxShadow: [
          // 主阴影 - 色彩强调
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: 4,
            offset: const Offset(0, 12),
          ),
          // 次级阴影 - 深度感
          BoxShadow(
            color: theme.colorScheme.shadow.withAlpha(20),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          // 顶部高光
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        // 装饰环
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.tertiary.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Center(
            // 内层图标容器
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.2),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: FilledButton.icon(
        onPressed: widget.onAction,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          widget.actionLabel!,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
