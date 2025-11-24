import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

import '../../models/agent.dart';
import '../../repositories/agent_repository.dart';
import '../../widgets/employee_card.dart';
import '../../widgets/employee_detail_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton_card.dart';

/// 员工列表 Tab
/// 显示当前用户的所有 Agent（员工）
class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab>
    with AutomaticKeepAliveClientMixin {
  final AgentRepository _repository = AgentRepository();
  final ScrollController _scrollController = ScrollController();

  List<Agent> _employees = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int? _nextCursor;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _repository.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await _repository.getUserAgents();
      if (mounted) {
        setState(() {
          _employees = page.agents;
          _nextCursor = page.nextCursor;
          _hasMore = page.hasNextPage;
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _nextCursor == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await _repository.getUserAgents(cursor: _nextCursor);
      if (mounted) {
        setState(() {
          _employees.addAll(page.agents);
          _nextCursor = page.nextCursor;
          _hasMore = page.hasNextPage;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    _nextCursor = null;
    _hasMore = true;
    await _loadEmployees();
  }

  /// 打开员工详情 Sheet
  void _onEmployeeTap(Agent employee) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EmployeeDetailSheet(
        employee: employee,
        onDelete: () => _deleteEmployee(employee),
      ),
    );
  }

  /// 删除员工
  Future<void> _deleteEmployee(Agent employee) async {
    try {
      await _repository.deleteAgent(employee.agentId);
      setState(() {
        _employees.removeWhere((e) => e.agentId == employee.agentId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).employeeDeleted),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${L10n.of(context).errorDeletingEmployee}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: theme.colorScheme.primary,
      child: _buildBody(context, theme, l10n),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, L10n l10n) {
    // 加载状态
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SkeletonCard(height: 80),
        ),
      );
    }

    // 错误状态
    if (_error != null && _employees.isEmpty) {
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
              onPressed: _loadEmployees,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.tryAgain),
            ),
          ],
        ),
      );
    }

    // 空状态
    if (_employees.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: l10n.noEmployeesYet,
        subtitle: l10n.noEmployeesHint,
        actionLabel: l10n.hireFirstEmployee,
        onAction: () {
          // 切换到招聘 Tab（通过父级 PageController）
          final teamPageState =
              context.findAncestorStateOfType<State<StatefulWidget>>();
          // TODO: 实现切换到招聘 Tab
        },
      );
    }

    // 员工列表
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 96, // 为底部导航栏留出空间
      ),
      itemCount: _employees.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _employees.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final employee = _employees[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: EmployeeCard(
            employee: employee,
            onTap: () => _onEmployeeTap(employee),
          ),
        );
      },
    );
  }

}
