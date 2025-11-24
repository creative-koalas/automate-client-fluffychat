import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';

import 'employees_tab.dart';
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
  late PageController _pageController;

  // Current selected tab index
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pageController = PageController();

    // Listen to TabController changes, sync with PageView
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_currentIndex != _tabController.index) {
      setState(() {
        _currentIndex = _tabController.index;
      });
      _pageController.animateToPage(
        _tabController.index,
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
      );
    }
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      _tabController.animateTo(index);
    }
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
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surface,
        automaticallyImplyLeading: false, // Remove back arrow
        title: Row(
          children: [
            // Team icon with subtle background
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.groups,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Title text
            Text(
              l10n.teamPageTitle,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildTabBar(context, theme),
        ),
      ),
      body: PageView(
        controller: controller._pageController,
        onPageChanged: controller._onPageChanged,
        children: const [
          EmployeesTab(),
          RecruitTab(),
          TrainingTab(),
        ],
      ),
      // Bottom navigation is now handled by MainScreen
    );
  }

  Widget _buildTabBar(BuildContext context, ThemeData theme) {
    final l10n = L10n.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: controller._tabController,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 3,
        indicatorColor: theme.colorScheme.primary,
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._currentIndex == 0
                      ? Icons.people
                      : Icons.people_outline,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(l10n.employeesTab),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._currentIndex == 1
                      ? Icons.person_add
                      : Icons.person_add_outlined,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(l10n.recruitTab),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller._currentIndex == 2
                      ? Icons.school
                      : Icons.school_outlined,
                  size: 20,
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
