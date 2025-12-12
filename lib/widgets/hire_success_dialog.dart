import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';

/// 雇佣成功对话框
/// 在用户成功雇佣员工后显示，提供更醒目的成功反馈
class HireSuccessDialog extends StatefulWidget {
  final String employeeName;
  final bool isFirstEmployee;
  final VoidCallback? onViewEmployee;
  final VoidCallback? onContinueHiring;

  const HireSuccessDialog({
    super.key,
    required this.employeeName,
    this.isFirstEmployee = false,
    this.onViewEmployee,
    this.onContinueHiring,
  });

  @override
  State<HireSuccessDialog> createState() => _HireSuccessDialogState();
}

class _HireSuccessDialogState extends State<HireSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
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
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: child,
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 成功图标 - 带动画的勾选图标
                _buildSuccessIcon(theme),
                const SizedBox(height: 20),

                // 标题
                Text(
                  widget.isFirstEmployee
                      ? l10n.firstEmployeeHired
                      : l10n.hireSuccessTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // 副标题
                Text(
                  l10n.hireSuccessMessage(widget.employeeName),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                // 首次雇佣的特殊提示
                if (widget.isFirstEmployee) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.firstEmployeeHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 入职中提示
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.employeeOnboardingHint,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 操作按钮
                Row(
                  children: [
                    // 继续招聘按钮
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onContinueHiring?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(l10n.continueHiring),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 查看员工按钮
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onViewEmployee?.call();
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.green,
                        ),
                        child: Text(l10n.viewEmployee),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.shade400,
                Colors.green.shade600,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3 * value),
                blurRadius: 20 * value,
                spreadRadius: 5 * value,
              ),
            ],
          ),
          child: Transform.scale(
            scale: value,
            child: const Icon(
              Icons.check_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/// 显示雇佣成功对话框的便捷方法
Future<void> showHireSuccessDialog({
  required BuildContext context,
  required String employeeName,
  bool isFirstEmployee = false,
  VoidCallback? onViewEmployee,
  VoidCallback? onContinueHiring,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => HireSuccessDialog(
      employeeName: employeeName,
      isFirstEmployee: isFirstEmployee,
      onViewEmployee: onViewEmployee,
      onContinueHiring: onContinueHiring,
    ),
  );
}
