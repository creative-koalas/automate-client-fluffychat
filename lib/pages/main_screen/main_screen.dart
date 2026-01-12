import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'package:psygo/pages/team/team_page.dart';

/// Main screen container for Messages and Team pages
/// Supports horizontal swipe navigation on mobile devices
class MainScreen extends StatefulWidget {
  final String? activeChat;
  final int initialPage;

  const MainScreen({
    super.key,
    this.activeChat,
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
            )
          : const TeamPage();
    }

    // Mobile mode: PageView without swipe + premium bottom navigation
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          ChatList(
            activeChat: widget.activeChat,
          ),
          const TeamPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface.withValues(alpha: 0.95),
              theme.colorScheme.surface,
            ],
          ),
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.04),
              blurRadius: 20,
              spreadRadius: -5,
              offset: const Offset(0, -8),
            ),
            BoxShadow(
              color: theme.colorScheme.shadow.withAlpha(12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  selectedIcon: Icons.chat_bubble_rounded,
                  label: l10n.messages,
                  isSelected: _currentPage == 0,
                  onTap: () => _onBottomNavTap(0),
                  theme: theme,
                ),
                _NavItem(
                  icon: Icons.groups_outlined,
                  selectedIcon: Icons.groups_rounded,
                  label: l10n.teamPageTitle,
                  isSelected: _currentPage == 1,
                  onTap: () => _onBottomNavTap(1),
                  theme: theme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义底部导航项 - 精美动画效果
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 24 : 16,
          vertical: isSelected ? 12 : 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 1.5,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: FluffyThemes.animationDuration,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: Icon(
                isSelected ? selectedIcon : icon,
                key: ValueKey(isSelected),
                size: 24,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
