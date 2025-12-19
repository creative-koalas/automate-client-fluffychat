import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/widgets/matrix.dart';
import 'package:go_router/go_router.dart';

import '../../models/agent.dart';
import '../../repositories/agent_repository.dart';
import '../../utils/retry_helper.dart';
import '../../widgets/employee_card.dart';
import '../../widgets/employee_detail_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton_card.dart';

/// 员工列表 Tab
/// 显示当前用户的所有 Agent（员工）
class EmployeesTab extends StatefulWidget {
  /// Callback to switch to recruit tab when employee list is empty
  final VoidCallback? onNavigateToRecruit;

  const EmployeesTab({super.key, this.onNavigateToRecruit});

  @override
  State<EmployeesTab> createState() => EmployeesTabState();
}

class EmployeesTabState extends State<EmployeesTab>
    with AutomaticKeepAliveClientMixin {
  final AgentRepository _repository = AgentRepository();
  final ScrollController _scrollController = ScrollController();

  List<Agent> _employees = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int? _nextCursor;
  bool _hasMore = true;

  // 轮询定时器：用于检测员工 isReady 状态变化
  Timer? _readyPollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 15);

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
    _stopReadyPolling();
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
      final page = await RetryHelper.withRetry(
        operation: () => _repository.getUserAgents(),
        maxRetries: 2,
        retryDelayMs: 3000,
        onRetry: (attempt, error) {
          // 可选：显示重试提示
          debugPrint('Retrying employee list load, attempt $attempt');
        },
      );
      if (mounted) {
        setState(() {
          _employees = page.agents;
          _nextCursor = page.nextCursor;
          _hasMore = page.hasNextPage;
          _isLoading = false;
        });
        // 检查是否需要启动/停止轮询
        _checkAndUpdatePolling();
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

  /// 检查是否有员工处于 isReady=false 状态，决定是否启动轮询
  void _checkAndUpdatePolling() {
    final hasUnreadyEmployees = _employees.any((e) => !e.isReady);

    if (hasUnreadyEmployees) {
      _startReadyPolling();
    } else {
      _stopReadyPolling();
    }
  }

  /// 启动轮询定时器（如果尚未启动）
  void _startReadyPolling() {
    if (_readyPollingTimer != null && _readyPollingTimer!.isActive) {
      return; // 已在轮询中
    }

    _readyPollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (mounted) {
        _refreshSilently();
      }
    });
  }

  /// 停止轮询定时器
  void _stopReadyPolling() {
    _readyPollingTimer?.cancel();
    _readyPollingTimer = null;
  }

  /// 静默刷新（不显示加载状态，用于轮询）
  /// 只更新现有员工的状态，不覆盖分页数据
  Future<void> _refreshSilently() async {
    try {
      final page = await _repository.getUserAgents();
      if (mounted) {
        // 只更新已存在员工的 isReady 状态，保留分页数据
        final updatedMap = {for (final e in page.agents) e.agentId: e};
        setState(() {
          _employees = _employees.map((e) {
            final updated = updatedMap[e.agentId];
            // 如果在最新数据中找到了这个员工，用新数据替换（主要是更新 isReady）
            return updated ?? e;
          }).toList();
        });
        // 刷新后检查是否需要继续轮询
        _checkAndUpdatePolling();
      }
    } catch (e) {
      // 静默刷新失败不影响 UI
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
        // 新加载的员工可能也有 isReady=false，检查是否需要启动轮询
        _checkAndUpdatePolling();
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

  /// Public method to refresh the employee list
  /// Called from parent when a new employee is hired
  Future<void> refreshEmployeeList() => _refresh();

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

  /// 长按显示快捷菜单
  void _onEmployeeLongPress(Agent employee, Offset tapPosition) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx + 1,
        tapPosition.dy + 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: [
        // 开始聊天
        PopupMenuItem<String>(
          value: 'chat',
          enabled: employee.isReady,
          child: Row(
            children: [
              Icon(
                Icons.chat_outlined,
                size: 20,
                color: employee.isReady
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.startChat,
                style: TextStyle(
                  color: employee.isReady ? null : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        // 查看详情
        PopupMenuItem<String>(
          value: 'details',
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(l10n.viewDetails),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // 优化（删除）
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.deleteEmployee,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'chat':
          _startChatWithEmployee(employee);
          break;
        case 'details':
          _onEmployeeTap(employee);
          break;
        case 'delete':
          _confirmDeleteEmployee(employee);
          break;
      }
    });
  }

  /// 快速开始聊天
  Future<void> _startChatWithEmployee(Agent employee) async {
    final l10n = L10n.of(context);

    if (!employee.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.employeeOnboarding),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final matrixUserId = employee.matrixUserId;
    if (matrixUserId == null || matrixUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.employeeNoMatrixId),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final client = Matrix.of(context).client;
      final existingDmRoomId = client.getDirectChatFromUserId(matrixUserId);

      if (existingDmRoomId != null) {
        if (mounted) {
          context.go('/rooms/$existingDmRoomId');
        }
        return;
      }

      // 创建新 DM
      final roomId = await client.startDirectChat(
        matrixUserId,
        enableEncryption: false,
      );

      if (mounted) {
        context.go('/rooms/$roomId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.errorStartingChat}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 确认优化对话框
  Future<void> _confirmDeleteEmployee(Agent employee) async {
    final l10n = L10n.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEmployee),
        content: Text(l10n.deleteEmployeeConfirm(employee.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteEmployee(employee);
    }
  }

  /// 优化员工
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

    // 错误状态 - 包裹在可滚动组件中以支持下拉刷新
    if (_error != null && _employees.isEmpty) {
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
                  onPressed: _loadEmployees,
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
    if (_employees.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: EmptyState(
            icon: Icons.people_outline,
            title: l10n.noEmployeesYet,
            subtitle: l10n.noEmployeesHint,
            actionLabel: l10n.hireFirstEmployee,
            onAction: () {
              // 切换到招聘 Tab
              widget.onNavigateToRecruit?.call();
            },
          ),
        ),
      );
    }

    // 员工列表 - PC端使用两列网格布局，移动端使用列表布局
    final isDesktop = FluffyThemes.isColumnMode(context);

    if (isDesktop) {
      // PC端：两列网格布局
      return GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 32,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 4, // 卡片宽高比
        ),
        itemCount: _employees.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _employees.length) {
            return const Center(child: CircularProgressIndicator());
          }

          final employee = _employees[index];
          return GestureDetector(
            // PC端使用右键触发快捷菜单
            onSecondaryTapDown: (details) {
              _onEmployeeLongPress(employee, details.globalPosition);
            },
            child: EmployeeCard(
              employee: employee,
              onTap: () => _onEmployeeTap(employee),
            ),
          );
        },
      );
    }

    // 移动端：列表布局
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 96,
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
          child: GestureDetector(
            onLongPressStart: (details) {
              _onEmployeeLongPress(employee, details.globalPosition);
            },
            child: EmployeeCard(
              employee: employee,
              onTap: () => _onEmployeeTap(employee),
            ),
          ),
        );
      },
    );
  }

}
