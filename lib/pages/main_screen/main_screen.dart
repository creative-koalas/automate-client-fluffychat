import 'package:flutter/material.dart';

import 'package:automate/config/themes.dart';
import 'package:automate/l10n/l10n.dart';
import 'package:automate/pages/chat_list/chat_list.dart';
import 'package:automate/automate/pages/team/team_page.dart';

/// Main screen container for Messages and Team pages
/// Supports horizontal swipe navigation on mobile devices
class MainScreen extends StatefulWidget {
  final String? activeChat;
  final String? activeSpace;
  final int initialPage;

  const MainScreen({
    super.key,
    this.activeChat,
    this.activeSpace,
    this.initialPage = 0,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync page when initialPage changes (e.g., from bottom nav tap)
    if (widget.initialPage != oldWidget.initialPage) {
      _currentPage = widget.initialPage;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    if (_currentPage != page) {
      setState(() {
        _currentPage = page;
      });
    }
  }

  void _onBottomNavTap(int index) {
    if (_currentPage != index) {
      setState(() {
        _currentPage = index;
      });
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Desktop/Tablet mode: no swipe, render directly
    if (isColumnMode) {
      return _currentPage == 0
          ? ChatList(
              activeChat: widget.activeChat,
              activeSpace: widget.activeSpace,
            )
          : const TeamPage();
    }

    // Mobile mode: PageView without swipe + bottom navigation
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const NeverScrollableScrollPhysics(), // Disable swipe between modules
        children: [
          ChatList(
            activeChat: widget.activeChat,
            activeSpace: widget.activeSpace,
          ),
          const TeamPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentPage,
        onDestinationSelected: _onBottomNavTap,
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        height: 80,
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: _currentPage == 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            selectedIcon: Icon(
              Icons.chat_bubble,
              color: theme.colorScheme.primary,
            ),
            label: l10n.messages,
          ),
          NavigationDestination(
            icon: Icon(
              Icons.groups_outlined,
              color: _currentPage == 1
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            selectedIcon: Icon(
              Icons.groups,
              color: theme.colorScheme.primary,
            ),
            label: l10n.teamPageTitle,
          ),
        ],
      ),
    );
  }
}
