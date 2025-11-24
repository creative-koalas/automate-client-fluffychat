import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';

import '../../models/agent_template.dart';
import '../../repositories/agent_template_repository.dart';
import '../../widgets/custom_hire_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/template_card.dart';
import '../../widgets/hire_dialog.dart';

/// 招聘中心 Tab
/// 展示可雇佣的 Agent 模板
class RecruitTab extends StatefulWidget {
  const RecruitTab({super.key});

  @override
  State<RecruitTab> createState() => _RecruitTabState();
}

class _RecruitTabState extends State<RecruitTab>
    with AutomaticKeepAliveClientMixin {
  final AgentTemplateRepository _repository = AgentTemplateRepository();

  List<AgentTemplate> _templates = [];
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final templates = await _repository.getActiveTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoading = false;
        });
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

  Future<void> _onTemplateTap(AgentTemplate template) async {
    final result = await showDialog<UnifiedCreateAgentResponse>(
      context: context,
      builder: (context) => HireDialog(
        template: template,
        repository: _repository,
      ),
    );

    _handleHireResult(result);
  }

  Future<void> _onCustomHire() async {
    final result = await showDialog<UnifiedCreateAgentResponse>(
      context: context,
      builder: (context) => CustomHireDialog(
        repository: _repository,
      ),
    );

    _handleHireResult(result);
  }

  void _handleHireResult(UnifiedCreateAgentResponse? result) {
    if (result != null && mounted) {
      // 雇佣成功，显示 Toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).hireSuccessGeneric),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: L10n.of(context).viewEmployee,
            onPressed: () {
              // 切换到员工 Tab
              // TODO: 通过父级控制器切换
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadTemplates,
        color: theme.colorScheme.primary,
        child: _buildBody(context, theme, l10n),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onCustomHire,
        icon: const Icon(Icons.add),
        label: Text(l10n.customHire),
        elevation: 4,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, L10n l10n) {
    // 加载状态
    if (_isLoading) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const SkeletonGridItem(height: 220),
      );
    }

    // 错误状态
    if (_error != null && _templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingData,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadTemplates,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.tryAgain),
            ),
          ],
        ),
      );
    }

    // 空状态
    if (_templates.isEmpty) {
      return EmptyState(
        icon: Icons.person_add_outlined,
        title: l10n.noTemplatesAvailable,
        subtitle: l10n.noTemplatesHint,
      );
    }

    // 模板列表
    return GridView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 96, // 为底部导航栏留出空间
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final template = _templates[index];
        return TemplateCard(
          template: template,
          onTap: () => _onTemplateTap(template),
        );
      },
    );
  }
}
