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

    // 将动画部分分离，只在需要时才使用 AnimatedBuilder
    if (isOnboarding) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          // 入职中状态时有微妙的发光效果
          final glowOpacity = _pulseAnimation.value * 0.3;
          final cardColor = Color.lerp(
            theme.colorScheme.surfaceContainerLow,
            Colors.orange.withValues(alpha: 0.08),
            _pulseAnimation.value * 0.3,
          );
          final borderColor = Color.lerp(
            theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            Colors.orange.withValues(alpha: 0.4),
            _pulseAnimation.value * 0.5,
          )!;

          return _buildCardContainer(
            context,
            theme,
            l10n,
            isOnboarding: true,
            glowOpacity: glowOpacity,
            cardColor: cardColor,
            borderColor: borderColor,
          );
        },
      );
    }

    // 非入职状态：静态渲染，无需动画
    return _buildCardContainer(
      context,
      theme,
      l10n,
      isOnboarding: false,
      cardColor: theme.colorScheme.surfaceContainerLow,
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
    );
  }

  Widget _buildCardContainer(
    BuildContext context,
    ThemeData theme,
    L10n l10n, {
    required bool isOnboarding,
    double glowOpacity = 0.0,
    required Color? cardColor,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isOnboarding
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: glowOpacity),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: theme.colorScheme.shadow.withAlpha(8),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Card(
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // 头像 + 状态指示器
                _buildAvatar(context, theme),
                const SizedBox(width: 12),

                // 员工信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 名称
                      Text(
                        widget.employee.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isOnboarding
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),

                      // 工作状态
                      Row(
                        children: [
                          _buildWorkStatusDot(theme),
                          if (widget.employee.isReady) const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _getWorkStatusText(l10n),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme) {
    final isOnboarding = !widget.employee.isReady;

    return SizedBox(
      width: isOnboarding ? 48 : 44,
      height: isOnboarding ? 48 : 44,
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
                        color: Colors.orange.withValues(
                          alpha: 0.3 + _pulseAnimation.value * 0.4,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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

    // 根据计算后的 work_status 判断状态
    Color dotColor;
    switch (widget.employee.computedWorkStatus) {
      case 'working':
        dotColor = Colors.green;  // 工作中 - 绿色
        break;
      case 'idle_long':
        dotColor = Colors.blue;   // 睡觉中 - 蓝色
        break;
      case 'idle':
      default:
        dotColor = Colors.orange; // 摸鱼中 - 橙色
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: 2,
        ),
      ),
    );
  }

  String _getWorkStatusText(L10n l10n) {
    // 入职中状态下显示不同文案
    if (!widget.employee.isReady) {
      return l10n.employeeOnboarding;
    }

    // 根据计算后的 work_status 判断状态，添加 emoji
    switch (widget.employee.computedWorkStatus) {
      case 'working':
        return '💼 ${l10n.employeeWorking}';   // 工作中
      case 'idle_long':
        return '😴 ${l10n.employeeSleeping}';  // 睡觉中
      case 'idle':
      default:
        return '🐟 ${l10n.employeeSlacking}';  // 摸鱼中
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
              color: Colors.orange.withValues(
                alpha: 0.1 + _pulseAnimation.value * 0.1,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.withValues(
                  alpha: 0.3 + _pulseAnimation.value * 0.2,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.withValues(alpha: 0.15),
            Colors.green.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: Colors.green.shade600,
          ),
          const SizedBox(width: 5),
          Text(
            l10n.employeeReady,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
