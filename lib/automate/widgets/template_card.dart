import 'package:flutter/material.dart';

import '../models/agent_template.dart';

/// 模板卡片组件
/// 用于招聘中心展示可雇佣的 Agent 模板
/// Grid 布局样式，包含头像、名称、副标题、技能标签
class TemplateCard extends StatelessWidget {
  final AgentTemplate template;
  final VoidCallback? onTap;

  const TemplateCard({
    super.key,
    required this.template,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头像
              _buildAvatar(theme),
              const SizedBox(height: 12),

              // 名称
              Text(
                template.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // 副标题
              Text(
                template.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // 技能标签
              _buildSkillTags(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: template.avatarUrl != null && template.avatarUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                template.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildAvatarFallback(theme),
              ),
            )
          : _buildAvatarFallback(theme),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.smart_toy_outlined,
        size: 32,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildSkillTags(ThemeData theme) {
    if (template.skillTags.isEmpty) {
      return const SizedBox.shrink();
    }

    // 最多显示 2 个标签
    final displayTags = template.skillTags.take(2).toList();
    final hasMore = template.skillTags.length > 2;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        ...displayTags.map((tag) => _buildTagChip(theme, tag)),
        if (hasMore)
          _buildTagChip(
            theme,
            '+${template.skillTags.length - 2}',
            isMore: true,
          ),
      ],
    );
  }

  Widget _buildTagChip(ThemeData theme, String label, {bool isMore = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isMore
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isMore
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
