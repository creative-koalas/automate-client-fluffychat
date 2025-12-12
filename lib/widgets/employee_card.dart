import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';

import '../models/agent.dart';

/// 员工卡片组件
/// 显示员工头像、名称、状态徽章、工作状态
/// 入职中状态会显示脉冲动画效果
class EmployeeCard extends StatefulWidget {
  final Agent employee;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const EmployeeCard({
    super.key,
    required this.employee,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends State<EmployeeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 只有入职中状态才启动动画
    if (!widget.employee.isReady) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EmployeeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 状态变化时更新动画
    if (widget.employee.isReady != oldWidget.employee.isReady) {
      if (!widget.employee.isReady) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isOnboarding = !widget.employee.isReady;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        // 入职中状态时有微妙的发光效果
        final glowOpacity = isOnboarding ? _pulseAnimation.value * 0.3 : 0.0;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: isOnboarding
                ? [
                    BoxShadow(
                      color: Colors.orange.withOpacity(glowOpacity),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Card(
            elevation: 0,
            color: isOnboarding
                ? Color.lerp(
                    theme.colorScheme.surfaceContainerLow,
                    Colors.orange.withOpacity(0.1),
                    _pulseAnimation.value * 0.3,
                  )
                : theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isOnboarding
                    ? Color.lerp(
                        theme.colorScheme.outlineVariant.withOpacity(0.3),
                        Colors.orange.withOpacity(0.5),
                        _pulseAnimation.value * 0.5,
                      )!
                    : theme.colorScheme.outlineVariant.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 头像 + 状态指示器
                    _buildAvatar(context, theme),
                    const SizedBox(width: 12),

                    // 员工信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 名称
                          Text(
                            widget.employee.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isOnboarding
                                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // 工作状态
                          Row(
                            children: [
                              _buildWorkStatusDot(theme),
                              const SizedBox(width: 6),
                              Text(
                                _getWorkStatusText(l10n),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 就绪状态徽章
                    _buildStatusBadge(context, theme, l10n),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme) {
    final isOnboarding = !widget.employee.isReady;

    return SizedBox(
      width: isOnboarding ? 60 : 56,
      height: isOnboarding ? 60 : 56,
      child: Stack(
        children: [
          // 入职中状态时头像有圆环动画
          if (isOnboarding)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.orange.withOpacity(
                          0.3 + _pulseAnimation.value * 0.4,
                        ),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            ),
          Positioned(
            left: isOnboarding ? 2 : 0,
            top: isOnboarding ? 2 : 0,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              ),
              child: widget.employee.avatarUrl != null &&
                      widget.employee.avatarUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Opacity(
                        opacity: isOnboarding ? 0.7 : 1.0,
                        child: Image.network(
                          widget.employee.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildAvatarFallback(theme),
                        ),
                      ),
                    )
                  : _buildAvatarFallback(theme),
            ),
          ),

          // 在线状态指示器（只在就绪状态下显示）
          if (widget.employee.isReady)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.employee.isWorking
                      ? Colors.green
                      : theme.colorScheme.outline,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Text(
        widget.employee.displayName.isNotEmpty
            ? widget.employee.displayName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildWorkStatusDot(ThemeData theme) {
    // 入职中状态下不显示工作状态点
    if (!widget.employee.isReady) {
      return const SizedBox.shrink();
    }

    // 根据 is_active 判断状态
    Color dotColor;
    if (widget.employee.isActive) {
      dotColor = Colors.green;  // 激活状态 = 工作中
    } else {
      dotColor = theme.colorScheme.outline;  // 未激活 = 摸鱼
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
    );
  }

  String _getWorkStatusText(L10n l10n) {
    // 入职中状态下显示不同文案
    if (!widget.employee.isReady) {
      return l10n.employeeOnboarding;
    }

    // 根据 is_active 判断状态
    if (widget.employee.isActive) {
      return l10n.employeeWorking;  // 激活 = 工作中
    } else {
      return l10n.employeeIdle;     // 未激活 = 摸鱼
    }
  }

  Widget _buildStatusBadge(BuildContext context, ThemeData theme, L10n l10n) {
    if (!widget.employee.isReady) {
      // 入职中状态 - 带脉冲效果
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(
                0.1 + _pulseAnimation.value * 0.1,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.withOpacity(
                  0.3 + _pulseAnimation.value * 0.2,
                ),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.employeeOnboarding,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // 就绪状态
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 14,
            color: Colors.green,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.employeeReady,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
