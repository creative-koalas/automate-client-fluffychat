import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';

import '../models/agent.dart';

/// 员工卡片组件
/// 显示员工头像、名称、状态徽章、工作状态
class EmployeeCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                      employee.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme) {
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
          ),
          child: employee.avatarUrl != null && employee.avatarUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    employee.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarFallback(theme),
                  ),
                )
              : _buildAvatarFallback(theme),
        ),

        // 在线状态指示器
        if (employee.isReady)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: employee.isWorking
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
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Text(
        employee.displayName.isNotEmpty
            ? employee.displayName[0].toUpperCase()
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
    Color dotColor;
    switch (employee.workStatus) {
      case 'working':
        dotColor = Colors.green;
        break;
      case 'idle_long':
        dotColor = Colors.orange;
        break;
      default:
        dotColor = theme.colorScheme.outline;
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
    switch (employee.workStatus) {
      case 'working':
        return l10n.employeeWorking;
      case 'idle_long':
        return l10n.employeeIdleLong;
      default:
        return l10n.employeeIdle;
    }
  }

  Widget _buildStatusBadge(BuildContext context, ThemeData theme, L10n l10n) {
    if (!employee.isReady) {
      // 入职中状态
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
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
