import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';

import '../models/agent_template.dart';
import '../repositories/agent_template_repository.dart';
import 'custom_network_image.dart';

/// 雇佣对话框
/// 用户点击模板后弹出，输入员工名称并确认雇佣
class HireDialog extends StatefulWidget {
  final AgentTemplate template;
  final AgentTemplateRepository repository;

  const HireDialog({
    super.key,
    required this.template,
    required this.repository,
  });

  @override
  State<HireDialog> createState() => _HireDialogState();
}

class _HireDialogState extends State<HireDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  String? _error;

  // 名称长度限制
  static const int _maxNameLength = 20;

  // 验证状态
  bool get _isNameTooLong => _nameController.text.trim().length > _maxNameLength;

  @override
  void initState() {
    super.initState();
    // 默认使用模板名称作为员工名（超长时截断）
    final templateName = widget.template.name;
    _nameController.text = templateName.length > _maxNameLength
        ? templateName.substring(0, _maxNameLength)
        : templateName;
    // 自动选中文本
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _invitationCodeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    final name = _nameController.text.trim();
    final invitationCode = _invitationCodeController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = L10n.of(context).employeeNameRequired;
      });
      return;
    }

    if (_isNameTooLong) {
      setState(() {
        _error = L10n.of(context).employeeNameTooLong;
      });
      return;
    }

    if (invitationCode.isEmpty) {
      setState(() {
        _error = L10n.of(context).invitationCodeRequired;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 调用统一创建接口，返回 UnifiedCreateAgentResponse
      final response = await widget.repository.hireFromTemplate(
        widget.template.id,
        name,
        invitationCode: invitationCode,
      );
      if (mounted) {
        // 返回响应对象，调用方可以获取 agentId、matrixUserId 等
        Navigator.of(context).pop(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Text(
                l10n.hireEmployee,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 模板信息预览
              _buildTemplatePreview(theme),
              const SizedBox(height: 24),

              // 员工名称输入
              TextField(
                controller: _nameController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  labelText: l10n.employeeName,
                  hintText: l10n.enterEmployeeName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _isNameTooLong
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _isNameTooLong
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  counterText: '${_nameController.text.length}/$_maxNameLength',
                  counterStyle: TextStyle(
                    color: _isNameTooLong
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  errorText: _isNameTooLong ? l10n.employeeNameTooLong : null,
                ),
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // 邀请码输入
              TextField(
                controller: _invitationCodeController,
                decoration: InputDecoration(
                  labelText: l10n.invitationCode,
                  hintText: l10n.enterInvitationCode,
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onConfirm(),
                enabled: !_isLoading,
              ),

              // 错误提示
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _onConfirm,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Text(l10n.confirmHire),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplatePreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: widget.template.avatarUrl != null &&
                    widget.template.avatarUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CustomNetworkImage(
                      widget.template.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarFallback(theme),
                    ),
                  )
                : _buildAvatarFallback(theme),
          ),
          const SizedBox(width: 14),

          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.template.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.template.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.smart_toy_outlined,
        size: 28,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
