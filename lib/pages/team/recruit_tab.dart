import 'package:flutter/material.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import '../../models/agent_template.dart';
import '../../repositories/agent_repository.dart';
import '../../repositories/agent_template_repository.dart';
import '../../utils/retry_helper.dart';
import '../../widgets/custom_hire_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/hire_success_dialog.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/template_card.dart';
import '../../widgets/hire_dialog.dart';

/// 招聘中心 Tab
/// 展示可雇佣的 Agent 模板
class RecruitTab extends StatefulWidget {
  /// Callback when user clicks "view employee" in SnackBar
  /// Triggers switch to Employees tab and refresh
  final VoidCallback? onEmployeeHired;

  /// Callback to refresh employee list in background
  /// Called automatically after successful hire
  final VoidCallback? onRefreshEmployees;

  const RecruitTab({
    super.key,
    this.onEmployeeHired,
    this.onRefreshEmployees,
  });

  @override
  State<RecruitTab> createState() => RecruitTabState();
}

class RecruitTabState extends State<RecruitTab>
    with AutomaticKeepAliveClientMixin {
  final AgentTemplateRepository _repository = AgentTemplateRepository();
  final AgentRepository _agentRepository = AgentRepository();

  List<AgentTemplate> _templates = [];
  bool _isLoading = true;
  String? _error;
  int _employeeCount = 0; // 用于判断是否是第一位员工

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadEmployeeCount();
  }

  @override
  void dispose() {
    _repository.dispose();
    _agentRepository.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeCount() async {
    try {
      final page = await _agentRepository.getUserAgents();
      if (mounted) {
        setState(() {
          _employeeCount = page.agents.length;
        });
      }
    } catch (_) {
      // 忽略错误，默认为0
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final templates = await RetryHelper.withRetry(
        operation: () => _repository.getActiveTemplates(),
        maxRetries: 2,
        retryDelayMs: 3000,
        onRetry: (attempt, error) {
          debugPrint('Retrying templates load, attempt $attempt');
        },
      );
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

  /// 公开的刷新方法，供外部调用
  Future<void> refresh() => _loadTemplates();

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
    final result = await showModalBottomSheet<UnifiedCreateAgentResponse>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true, // 允许点击外部关闭
      enableDrag: true, // 允许拖拽关闭
      builder: (context) => CustomHireDialog(
        repository: _repository,
      ),
    );

    _handleHireResult(result);
  }

  void _handleHireResult(UnifiedCreateAgentResponse? result) {
    if (result != null && mounted) {
      // 自动刷新员工列表（后台刷新，用户切回时能看到新员工）
      widget.onRefreshEmployees?.call();

      // 判断是否是第一位员工
      final isFirstEmployee = _employeeCount == 0;

      // 雇佣后更新员工计数
      setState(() {
        _employeeCount++;
      });

      // 从 matrixUserId 提取员工名称 (@name:domain -> name)
      String employeeName = 'Employee';
      if (result.matrixUserId.isNotEmpty) {
        final userId = result.matrixUserId;
        if (userId.startsWith('@') && userId.contains(':')) {
          employeeName = userId.substring(1, userId.indexOf(':'));
        } else {
          employeeName = userId;
        }
      }

      // 显示成功对话框
      showHireSuccessDialog(
        context: context,
        employeeName: employeeName,
        isFirstEmployee: isFirstEmployee,
        onViewEmployee: () {
          widget.onEmployeeHired?.call();
        },
        onContinueHiring: () {
          // 留在当前页面，不做任何操作
        },
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
    final isDesktop = FluffyThemes.isColumnMode(context);

    // 加载状态
    if (_isLoading) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth, isDesktop);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: crossAxisCount * 2,
            itemBuilder: (context, index) => const SkeletonGridItem(height: 220),
          );
        },
      );
    }

    // 错误状态 - 包裹在可滚动组件中以支持下拉刷新
    if (_error != null && _templates.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
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
          ),
        ),
      );
    }

    // 空状态 - 包裹在可滚动组件中以支持下拉刷新
    if (_templates.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: EmptyState(
            icon: Icons.person_add_outlined,
            title: l10n.noTemplatesAvailable,
            subtitle: l10n.noTemplatesHint,
          ),
        ),
      );
    }

    // 模板列表 - 响应式网格布局
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth, isDesktop);
        // 根据列数调整宽高比
        final aspectRatio = isDesktop ? (crossAxisCount >= 4 ? 0.68 : 0.72) : 0.72;

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 96, // 为底部导航栏留出空间
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
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
      },
    );
  }

  /// 计算网格列数
  int _calculateCrossAxisCount(double width, bool isDesktop) {
    if (!isDesktop) return 2; // 移动端固定 2 列

    // PC端：根据宽度自适应列数
    const minCardWidth = 180.0;
    final availableWidth = width - 32; // 减去左右 padding
    int crossAxisCount = (availableWidth / minCardWidth).floor();
    return crossAxisCount.clamp(2, 6); // 2-6 列
  }
}
