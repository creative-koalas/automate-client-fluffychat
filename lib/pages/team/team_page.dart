import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';

import 'package:psygo/pages/wallet/wallet_page.dart';
import 'employees_tab.dart' show EmployeesTab, EmployeesTabState;
import 'recruit_tab.dart';
import 'training_tab.dart';

/// Team main page
/// Contains three tabs: Employees, Recruit, Training
/// Supports swipe to switch between tabs
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => TeamPageController();
}

class TeamPageController extends State<TeamPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // GlobalKey to access EmployeesTab state
  final GlobalKey<EmployeesTabState> _employeesTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 监听 tab 变化以更新图标状态
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // 仅用于刷新图标状态，不需要手动同步 PageView
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  /// Switch to Employees tab and refresh the list
  /// Called after successful employee hire
  void switchToEmployeesAndRefresh() {
    _tabController.animateTo(0);
    // Trigger refresh on employees tab
    Future.delayed(const Duration(milliseconds: 100), () {
      _employeesTabKey.currentState?.refreshEmployeeList();
    });
  }

  /// Switch to Recruit tab
  /// Called from empty state in Employees tab
  void switchToRecruitTab() {
    _tabController.animateTo(1);
  }

  /// Refresh employee list without switching tab
  /// Called after successful hire (background refresh)
  void refreshEmployeeList() {
    _employeesTabKey.currentState?.refreshEmployeeList();
  }

  @override
  Widget build(BuildContext context) => TeamPageView(this);
}

class TeamPageView extends StatelessWidget {
  final TeamPageController controller;

  const TeamPageView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.08),
                theme.colorScheme.surface,
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.05),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            // Team icon with gradient background
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Title text
            Text(
              l10n.teamPageTitle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          // Wallet button with badge style
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.account_balance_wallet_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              tooltip: l10n.walletTitle,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WalletPage(),
                  ),
                );
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _buildTabBar(context, theme),
        ),
      ),
      // TabBarView 内部使用 PageView，自动与 TabController 同步
      // 左右滑动和点击菜单都由同一个 TabController 驱动
      body: TabBarView(
        controller: controller._tabController,
        children: [
          EmployeesTab(
            key: controller._employeesTabKey,
            onNavigateToRecruit: controller.switchToRecruitTab,
          ),
          RecruitTab(
            onEmployeeHired: controller.switchToEmployeesAndRefresh,
            onRefreshEmployees: controller.refreshEmployeeList,
          ),
          const TrainingTab(),
        ],
      ),
      // Bottom navigation is now handled by MainScreen
    );
  }

  Widget _buildTabBar(BuildContext context, ThemeData theme) {
    final l10n = L10n.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
            theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: controller._tabController,
        labelColor: Colors.white,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(12),
        tabs: [
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._tabController.index == 0
                      ? Icons.people_rounded
                      : Icons.people_outline_rounded,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(l10n.employeesTab),
              ],
            ),
          ),
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._tabController.index == 1
                      ? Icons.person_add_rounded
                      : Icons.person_add_alt_outlined,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(l10n.recruitTab),
              ],
            ),
          ),
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._tabController.index == 2
                      ? Icons.school_rounded
                      : Icons.school_outlined,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(l10n.trainingTab),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
