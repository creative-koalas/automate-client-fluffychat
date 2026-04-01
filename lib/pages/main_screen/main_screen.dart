import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'package:psygo/pages/team/team_page.dart';
import 'package:psygo/widgets/matrix.dart';

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

  // 与 PC 顶部导航保持一致：消息未读总数（按 room.notificationCount 累加）
  static int _cachedUnreadCount = 0;
  int _unreadCount = 0;
  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);
    _unreadCount = _cachedUnreadCount;

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
      _cachedUnreadCount = count;
      if (_unreadCount != count) {
        setState(() => _unreadCount = count);
      }
    } catch (_) {}
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
          duration: FluffyThemes.durationFast,
          curve: FluffyThemes.curveStandard,
        );
      }
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
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
          : const TeamPage(
              isVisible: true,
            );
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
          TeamPage(
            isVisible: _currentPage == 1,
          ),
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
          boxShadow: FluffyThemes.layeredShadow(
            context,
            elevation: FluffyThemes.elevationLg,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluffyThemes.spacing20,
              vertical: FluffyThemes.spacing8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  selectedIcon: Icons.chat_bubble_rounded,
                  label: l10n.messages,
                  isSelected: _currentPage == 0,
                  badgeCount: _unreadCount,
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
  final int badgeCount;
  final VoidCallback onTap;
  final ThemeData theme;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: FluffyThemes.durationFast,
          curve: FluffyThemes.curveBounce,
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
            borderRadius: BorderRadius.circular(FluffyThemes.radiusXl),
            border: isSelected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  )
                : null,
            boxShadow: isSelected
                ? FluffyThemes.layeredShadow(
                    context,
                    elevation: FluffyThemes.elevationMd,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(FluffyThemes.radiusXl),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(FluffyThemes.radiusXl),
              splashColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              highlightColor: theme.colorScheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      isSelected ? FluffyThemes.spacing24 : FluffyThemes.spacing16,
                  vertical:
                      isSelected ? FluffyThemes.spacing12 : FluffyThemes.spacing8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: FluffyThemes.durationFast,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                      child: Icon(
                        isSelected ? selectedIcon : icon,
                        key: ValueKey(isSelected),
                        size: FluffyThemes.iconSizeMd,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    AnimatedSize(
                      duration: FluffyThemes.durationFast,
                      curve: FluffyThemes.curveStandard,
                      child: isSelected
                          ? Padding(
                              padding: const EdgeInsets.only(
                                left: FluffyThemes.spacing8,
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: FluffyThemes.fontSizeMd,
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
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: TextStyle(
                  color: theme.colorScheme.onError,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
