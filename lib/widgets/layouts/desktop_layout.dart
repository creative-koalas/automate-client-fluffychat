import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat/chat.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'package:psygo/pages/team/employees_tab.dart';
import 'package:psygo/pages/team/recruit_tab.dart';
import 'package:psygo/pages/team/training_tab.dart';
import 'package:psygo/pages/wallet/wallet_page.dart';
import 'package:psygo/utils/fluffy_share.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/collapsible_sidebar.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/layouts/empty_page.dart';
import 'package:psygo/widgets/matrix.dart';

/// PC 端主页索引
enum DesktopPageIndex {
  messages(0),
  employees(1),
  recruitment(2),
  training(3);

  final int value;
  const DesktopPageIndex(this.value);
}

/// PC 端桌面布局 - 包含可收缩侧边栏
/// 只用于桌面端，不影响移动端
class DesktopLayout extends StatefulWidget {
  final String? activeChat;
  final DesktopPageIndex initialPage;

  const DesktopLayout({
    super.key,
    this.activeChat,
    this.initialPage = DesktopPageIndex.messages,
  });

  /// 清除用户缓存（退出登录时调用）
  static void clearUserCache() {
    _DesktopLayoutState.clearUserCache();
  }

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
  // 使用静态变量保存当前页面，这样即使 widget 重建也能恢复到用户选择的页面
  static DesktopPageIndex _savedCurrentPage = DesktopPageIndex.messages;
  // 保存消息列表宽度
  static double _chatListWidth = FluffyThemes.columnWidth;
  // 缓存未读计数
  static int _cachedUnreadCount = 0;
  // Profile 版本号（用于通知实例刷新缓存）
  static int _profileVersion = 0;

  /// 清除用户缓存（退出登录或更新头像时调用）
  static void clearUserCache() {
    debugPrint('[DesktopLayout] clearUserCache called');
    _cachedUnreadCount = 0;
    _profileVersion++; // 递增版本号，通知实例刷新
  }

  // Profile Future（实例变量，和设置页面一样的模式）
  Future<Profile>? _profileFuture;
  int _lastProfileVersion = 0; // 记录上次使用的版本号

  // 消息列表最小/最大宽度
  static const double _minChatListWidth = 280.0;
  static const double _maxChatListWidth = 500.0;

  late DesktopPageIndex _currentPage;
  int _unreadCount = 0;
  bool _isMenuOpen = false;
  bool _isDraggingDivider = false;

  // 监听同步事件以更新未读计数
  StreamSubscription? _syncSubscription;

  // 各页面的 Key，用于刷新
  final GlobalKey<EmployeesTabState> _employeesTabKey = GlobalKey();
  final GlobalKey<RecruitTabState> _recruitTabKey = GlobalKey();
  final GlobalKey<TrainingTabState> _trainingTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 如果有 activeChat，说明是要打开聊天，切换到消息页面
    // 否则恢复到之前保存的页面
    _currentPage = widget.activeChat != null
        ? DesktopPageIndex.messages
        : _savedCurrentPage;
    // 先使用缓存的未读计数
    _unreadCount = _cachedUnreadCount;
    // 延迟到 context 可用后初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateUnreadCount();
      _setupSyncListener();
    });
  }

  void _setupSyncListener() {
    if (!mounted) return;
    try {
      final client = Matrix.of(context).clientOrNull;
      if (client == null) return;
      _syncSubscription = client.onSync.stream.listen((_) {
        _updateUnreadCount();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(DesktopLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 activeChat 变化且当前不在消息页面时，自动切换到消息页面
    if (widget.activeChat != null &&
        widget.activeChat != oldWidget.activeChat &&
        _currentPage != DesktopPageIndex.messages) {
      setState(() => _currentPage = DesktopPageIndex.messages);
    }
  }

  void _updateUnreadCount() {
    if (!mounted) return;
    try {
      final client = Matrix.of(context).clientOrNull;
      if (client == null) return;
      var count = 0;
      for (final room in client.rooms) {
        if (room.isUnreadOrInvited) {
          count += room.notificationCount;
        }
      }
      // 更新缓存和状态
      _cachedUnreadCount = count;
      if (_unreadCount != count) {
        setState(() => _unreadCount = count);
      }
    } catch (_) {}
  }

  void _onPageSelected(int index) {
    final newPage = DesktopPageIndex.values[index];
    if (_currentPage != newPage) {
      setState(() => _currentPage = newPage);
      _savedCurrentPage = newPage; // 保存当前页面状态
      // 当切换到非消息页面时，清除路由中的 roomId，这样下次点击"开始聊天"时路由会变化
      if (newPage != DesktopPageIndex.messages && widget.activeChat != null) {
        context.go('/rooms');
      }
    }
    // 点击按钮时刷新对应页面
    _refreshCurrentPage(newPage);
  }

  /// 刷新当前选中的页面
  void _refreshCurrentPage(DesktopPageIndex page) {
    switch (page) {
      case DesktopPageIndex.messages:
        // 消息页面由 Matrix sync 自动刷新
        break;
      case DesktopPageIndex.employees:
        _employeesTabKey.currentState?.refreshEmployeeList();
        break;
      case DesktopPageIndex.recruitment:
        _recruitTabKey.currentState?.refresh();
        break;
      case DesktopPageIndex.training:
        _trainingTabKey.currentState?.refresh();
        break;
    }
  }

  /// 招聘成功后切换到员工页面并刷新
  void _switchToEmployeesAndRefresh() {
    setState(() => _currentPage = DesktopPageIndex.employees);
    Future.delayed(const Duration(milliseconds: 100), () {
      _employeesTabKey.currentState?.refreshEmployeeList();
    });
  }

  /// 刷新员工列表
  void _refreshEmployeeList() {
    _employeesTabKey.currentState?.refreshEmployeeList();
  }

  /// 切换到招聘页面
  void _switchToRecruitment() {
    setState(() => _currentPage = DesktopPageIndex.recruitment);
  }

  /// 菜单选项 - 完全按照 ClientChooserButton 的方式
  List<PopupMenuEntry<Object>> _buildMenuItems(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildMenuItem(IconData icon, String text, Color? iconColor) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? theme.colorScheme.primary).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: _SettingsAction.newGroup,
        child: buildMenuItem(
          Icons.group_add_rounded,
          L10n.of(context).createGroup,
          theme.colorScheme.tertiary,
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.setStatus,
        child: buildMenuItem(
          Icons.edit_rounded,
          L10n.of(context).setStatus,
          theme.colorScheme.secondary,
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.invite,
        child: buildMenuItem(
          Icons.adaptive.share_rounded,
          L10n.of(context).inviteContact,
          theme.colorScheme.primary,
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.settings,
        child: buildMenuItem(
          Icons.settings_rounded,
          L10n.of(context).settings,
          theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// 菜单选择处理 - 完全按照 ClientChooserButton 的方式
  void _onMenuSelected(Object object) async {
    if (object is _SettingsAction) {
      switch (object) {
        case _SettingsAction.newGroup:
          context.go('/rooms/newgroup');
          break;
        case _SettingsAction.invite:
          FluffyShare.shareInviteLink(context);
          break;
        case _SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case _SettingsAction.setStatus:
          _handleSetStatus();
          break;
      }
    }
  }

  /// 处理设置状态
  Future<void> _handleSetStatus() async {
    final matrix = Matrix.of(context);
    final client = matrix.clientOrNull;
    if (client == null) return;
    final currentPresence = await client.fetchCurrentPresence(client.userID!);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).setStatus,
      message: L10n.of(context).leaveEmptyToClearStatus,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).statusExampleMessage,
      maxLines: 6,
      minLines: 1,
      maxLength: 255,
      initialText: currentPresence.statusMsg,
    );
    if (input == null) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => client.setPresence(
        client.userID!,
        PresenceType.online,
        statusMsg: input,
      ),
    );
  }

  /// 构建自适应宽度的 header - 使用 FutureBuilder 和设置页面一样的模式
  Widget _buildAdaptiveHeader() {
    final theme = Theme.of(context);
    final matrix = Matrix.of(context);
    final client = matrix.clientOrNull;
    // 客户端未初始化时显示占位符
    if (client == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final userId = client.userID ?? '';
    // 检查版本号是否变化（设置页面更新头像后会递增版本号）
    if (_lastProfileVersion != _profileVersion) {
      _profileFuture = null;
      _lastProfileVersion = _profileVersion;
    }
    // 初始化 profileFuture（和设置页面一样的逻辑）
    _profileFuture ??= client.getProfileFromUserId(userId);

    return FutureBuilder<Profile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        var localpart = '用户';
        if (userId.startsWith('@') && userId.contains(':')) {
          localpart = userId.substring(1, userId.indexOf(':'));
        }
        final profile = snapshot.data;
        final displayName = profile?.displayName ?? localpart;
        final avatarUrl = profile?.avatarUrl;

        // 预构建头像组件，避免动画期间重复创建
        final avatar = RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withAlpha(80),
                  theme.colorScheme.tertiary.withAlpha(60),
                ],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
              ),
              child: Avatar(
                mxContent: avatarUrl,
                name: displayName,
                size: 36,
              ),
            ),
          ),
        );

        // 使用 LayoutBuilder 自适应宽度
        return LayoutBuilder(
          builder: (context, constraints) {
            final showName = constraints.maxWidth > 150;

            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showName ? 16 : 0,
                  vertical: 12,
                ),
                child: Material(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(99),
                  color: Colors.transparent,
                  child: PopupMenuButton<Object>(
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    onOpened: () => setState(() => _isMenuOpen = true),
                    onCanceled: () => setState(() => _isMenuOpen = false),
                    onSelected: (value) {
                      setState(() => _isMenuOpen = false);
                      _onMenuSelected(value);
                    },
                    itemBuilder: _buildMenuItems,
                    child: showName
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          avatar,
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  userId,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : avatar,
              ),
            ),
          ),
        );
          },
        );
      },
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);

    switch (_currentPage) {
      case DesktopPageIndex.messages:
        // 消息页面：聊天列表 + 聊天详情（双栏布局，可调整大小）
        return LayoutBuilder(
          builder: (context, constraints) {
            return MouseRegion(
              cursor: _isDraggingDivider
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.basic,
              child: Listener(
                onPointerMove: _isDraggingDivider
                    ? (event) {
                        // 计算新宽度：鼠标相对于内容区域左边的位置
                        final newWidth = event.localPosition.dx.clamp(
                          _minChatListWidth,
                          _maxChatListWidth,
                        );
                        if (newWidth != _chatListWidth) {
                          setState(() => _chatListWidth = newWidth);
                        }
                      }
                    : null,
                onPointerUp: _isDraggingDivider
                    ? (_) => setState(() => _isDraggingDivider = false)
                    : null,
                child: Row(
                  children: [
                    // 聊天列表（可调整宽度）
                    SizedBox(
                      width: _chatListWidth,
                      child: ChatList(
                        activeChat: widget.activeChat,
                        displayNavigationRail: false,
                      ),
                    ),
                    // 可拖拽分隔线
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) {
                          setState(() => _isDraggingDivider = true);
                        },
                        child: Container(
                          width: 8,
                          color: Colors.transparent,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: _isDraggingDivider ? 4 : 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: _isDraggingDivider
                                      ? [
                                          theme.colorScheme.primary.withAlpha(100),
                                          theme.colorScheme.primary,
                                          theme.colorScheme.primary.withAlpha(100),
                                        ]
                                      : [
                                          theme.dividerColor.withAlpha(60),
                                          theme.dividerColor,
                                          theme.dividerColor.withAlpha(60),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 聊天详情
                    Expanded(
                      child: widget.activeChat != null
                          ? ChatPage(roomId: widget.activeChat!)
                          : const EmptyPage(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      case DesktopPageIndex.employees:
        // 员工页面：全宽显示
        return Scaffold(
          appBar: AppBar(
            title: const Text('员工管理'),
            automaticallyImplyLeading: false,
            actions: [
              // 钱包按钮
              IconButton(
                icon: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                tooltip: L10n.of(context).walletTitle,
                onPressed: () {
                  // PC 端以独立窗口形式打开
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: const SizedBox(
                          width: 420,
                          height: 680,
                          child: WalletPage(showBackButton: false),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: EmployeesTab(
            key: _employeesTabKey,
            onNavigateToRecruit: _switchToRecruitment,
          ),
        );
      case DesktopPageIndex.recruitment:
        // 招聘页面：全宽显示
        return Scaffold(
          appBar: AppBar(
            title: const Text('招聘中心'),
            automaticallyImplyLeading: false,
          ),
          body: RecruitTab(
            key: _recruitTabKey,
            onEmployeeHired: _switchToEmployeesAndRefresh,
            onRefreshEmployees: _refreshEmployeeList,
          ),
        );
      case DesktopPageIndex.training:
        // 培训页面：全宽显示
        return Scaffold(
          appBar: AppBar(
            title: const Text('培训市场'),
            automaticallyImplyLeading: false,
          ),
          body: TrainingTab(key: _trainingTabKey),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final menuItems = [
      SidebarMenuItem(
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
        label: '消息',
        badgeCount: _unreadCount,
      ),
      const SidebarMenuItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: '员工',
      ),
      const SidebarMenuItem(
        icon: Icons.person_add_outlined,
        selectedIcon: Icons.person_add,
        label: '招聘',
      ),
      const SidebarMenuItem(
        icon: Icons.school_outlined,
        selectedIcon: Icons.school,
        label: '培训',
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          // 可收缩侧边栏 - 使用单个自适应 header 避免 widget 切换导致 PopupMenu 失效
          CollapsibleSidebar(
            items: menuItems,
            selectedIndex: _currentPage.value,
            onItemSelected: _onPageSelected,
            header: _buildAdaptiveHeader(),
            backgroundColor: theme.colorScheme.surface,
            preventCollapse: _isMenuOpen,
          ),
          // 主内容区
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }
}

/// 设置菜单选项
enum _SettingsAction {
  newGroup,
  setStatus,
  invite,
  settings,
}
