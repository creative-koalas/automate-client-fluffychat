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

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
  late DesktopPageIndex _currentPage;
  int _unreadCount = 0;
  bool _isMenuOpen = false;

  // 员工页面的 Key，用于刷新
  final GlobalKey<EmployeesTabState> _employeesTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final matrix = Matrix.of(context);
        final client = matrix.client;
        int count = 0;
        for (final room in client.rooms) {
          if (room.isUnreadOrInvited) {
            count += room.notificationCount;
          }
        }
        if (_unreadCount != count) {
          setState(() => _unreadCount = count);
        }
      } catch (_) {}
    });
  }

  void _onPageSelected(int index) {
    final newPage = DesktopPageIndex.values[index];
    if (_currentPage != newPage) {
      setState(() => _currentPage = newPage);
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
    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: _SettingsAction.newGroup,
        child: Row(
          children: [
            const Icon(Icons.group_add_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).createGroup),
          ],
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.setStatus,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).setStatus),
          ],
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.invite,
        child: Row(
          children: [
            Icon(Icons.adaptive.share_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).inviteContact),
          ],
        ),
      ),
      PopupMenuItem(
        value: _SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).settings),
          ],
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
    final client = matrix.client;
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

  /// 构建自适应宽度的 header - 使用单个 widget 避免重建问题
  Widget _buildAdaptiveHeader() {
    final theme = Theme.of(context);
    final matrix = Matrix.of(context);

    return FutureBuilder<Profile>(
      future: matrix.client.isLogged() ? matrix.client.fetchOwnProfile() : null,
      builder: (context, snapshot) {
        final userId = matrix.client.userID ?? '';
        String localpart = '用户';
        if (userId.startsWith('@') && userId.contains(':')) {
          localpart = userId.substring(1, userId.indexOf(':'));
        }
        final displayName = snapshot.data?.displayName ?? localpart;

        // 使用 LayoutBuilder 自适应宽度，避免切换 widget 导致 PopupMenu 失效
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
                              Avatar(
                                mxContent: snapshot.data?.avatarUrl,
                                name: displayName,
                                size: 40,
                              ),
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
                        : Avatar(
                            mxContent: snapshot.data?.avatarUrl,
                            name: displayName,
                            size: 44,
                          ),
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
        // 消息页面：聊天列表 + 聊天详情（双栏布局）
        return Row(
          children: [
            // 聊天列表
            SizedBox(
              width: FluffyThemes.columnWidth,
              child: ChatList(
                activeChat: widget.activeChat,
                displayNavigationRail: false,
              ),
            ),
            // 分隔线
            Container(
              width: 1,
              color: theme.dividerColor,
            ),
            // 聊天详情
            Expanded(
              child: widget.activeChat != null
                  ? ChatPage(roomId: widget.activeChat!)
                  : const EmptyPage(),
            ),
          ],
        );
      case DesktopPageIndex.employees:
        // 员工页面：全宽显示
        return Scaffold(
          appBar: AppBar(
            title: const Text('员工管理'),
            automaticallyImplyLeading: false,
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
          body: const TrainingTab(),
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
      SidebarMenuItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: '员工',
      ),
      SidebarMenuItem(
        icon: Icons.person_add_outlined,
        selectedIcon: Icons.person_add,
        label: '招聘',
      ),
      SidebarMenuItem(
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
            collapsedHeader: _buildAdaptiveHeader(),
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
