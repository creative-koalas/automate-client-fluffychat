import 'package:flutter/material.dart';

/// 侧边栏菜单项数据
class SidebarMenuItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final int? badgeCount;
  final VoidCallback? onTap;

  const SidebarMenuItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.badgeCount,
    this.onTap,
  });
}

/// 可收缩侧边栏组件
/// 鼠标悬停时展开，离开时收缩
class CollapsibleSidebar extends StatefulWidget {
  final List<SidebarMenuItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onItemSelected;
  final Widget? header;
  final Widget? collapsedHeader;
  final double expandedWidth;
  final double collapsedWidth;
  final Duration animationDuration;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? hoverColor;
  final bool preventCollapse;

  const CollapsibleSidebar({
    super.key,
    required this.items,
    this.selectedIndex = 0,
    this.onItemSelected,
    this.header,
    this.collapsedHeader,
    this.expandedWidth = 240,
    this.collapsedWidth = 72,
    this.animationDuration = const Duration(milliseconds: 200),
    this.backgroundColor,
    this.selectedColor,
    this.hoverColor,
    this.preventCollapse = false,
  });

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;

  // 静态变量：记录是否已经预热过
  static bool _hasWarmedUp = false;

  // 是否处于首次展示状态（1秒内不响应鼠标事件）
  bool _isFirstShow = false;

  @override
  void initState() {
    super.initState();

    // 首次启动时从展开状态开始，这样 shader 立即被编译
    final startExpanded = !_hasWarmedUp;
    if (!_hasWarmedUp) {
      _hasWarmedUp = true;
    }

    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      // 首次启动时从 1.0（展开）开始
      value: startExpanded ? 1.0 : 0.0,
    );
    _widthAnimation = Tween<double>(
      begin: widget.collapsedWidth,
      end: widget.expandedWidth,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // 首次启动时，等界面渲染完成后再开始计时，然后自动收缩
    if (startExpanded) {
      _isFirstShow = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _isFirstShow) {
            _isFirstShow = false;
            _animationController.reverse();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent event) {
    // 首次展示期间不响应鼠标事件
    if (_isFirstShow) return;

    if (!_animationController.isAnimating || _animationController.status == AnimationStatus.reverse) {
      _animationController.forward();
    }
  }

  void _onExit(PointerEvent event) {
    // 首次展示期间不响应鼠标事件
    if (_isFirstShow) return;

    // 当 preventCollapse 为 true 时（如弹出菜单打开时），不收缩侧边栏
    if (!widget.preventCollapse) {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = widget.backgroundColor ?? theme.colorScheme.surface;
    final selectedColor = widget.selectedColor ??
        theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
    final hoverColor = widget.hoverColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _widthAnimation,
          builder: (context, child) {
            final progress = (_widthAnimation.value - widget.collapsedWidth) /
                (widget.expandedWidth - widget.collapsedWidth);
            return Container(
              width: _widthAnimation.value,
              decoration: BoxDecoration(
                color: backgroundColor,
                boxShadow: progress > 0.3
                    ? [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withAlpha(30)
                              : Colors.black.withAlpha(8),
                          blurRadius: 12,
                          offset: const Offset(2, 0),
                        ),
                      ]
                    : null,
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor.withValues(alpha: progress > 0.3 ? 0 : 0.08),
                    width: 1,
                  ),
                ),
              ),
              child: child,
            );
          },
          child: Column(
            children: [
              // Header
              if (widget.header != null || widget.collapsedHeader != null)
                _buildHeader(),

              const SizedBox(height: 12),

              // Menu items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) => _SidebarItem(
                    item: widget.items[index],
                    isSelected: index == widget.selectedIndex,
                    widthAnimation: _widthAnimation,
                    expandedWidth: widget.expandedWidth,
                    collapsedWidth: widget.collapsedWidth,
                    selectedColor: selectedColor,
                    hoverColor: hoverColor,
                    onTap: () {
                      widget.onItemSelected?.call(index);
                      widget.items[index].onTap?.call();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return widget.header ?? const SizedBox(height: 60);
  }
}

class _SidebarItem extends StatefulWidget {
  final SidebarMenuItem item;
  final bool isSelected;
  final Animation<double> widthAnimation;
  final double expandedWidth;
  final double collapsedWidth;
  final Color selectedColor;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.item,
    required this.isSelected,
    required this.widthAnimation,
    required this.expandedWidth,
    required this.collapsedWidth,
    required this.selectedColor,
    required this.hoverColor,
    this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = widget.isSelected && widget.item.selectedIcon != null
        ? widget.item.selectedIcon!
        : widget.item.icon;

    final iconColor = widget.isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: 52,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? widget.selectedColor
                  : (_isHovered ? widget.hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AnimatedBuilder(
              animation: widget.widthAnimation,
              builder: (context, _) {
                final progress = (widget.widthAnimation.value - widget.collapsedWidth) /
                    (widget.expandedWidth - widget.collapsedWidth);
                final showExpanded = progress > 0.5;

                if (showExpanded) {
                  return _buildExpandedContent(theme, icon, iconColor, progress);
                } else {
                  return _buildCollapsedContent(theme, icon, iconColor);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme, IconData icon, Color iconColor, double progress) {
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.item.label,
              style: TextStyle(
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.item.badgeCount != null && widget.item.badgeCount! > 0)
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.error,
                    theme.colorScheme.error.withAlpha(220),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.error.withAlpha(60),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.item.badgeCount! > 99 ? '99+' : '${widget.item.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollapsedContent(ThemeData theme, IconData icon, Color iconColor) {
    final hasBadge = widget.item.badgeCount != null && widget.item.badgeCount! > 0;

    if (hasBadge) {
      return Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              Center(child: Icon(icon, color: iconColor, size: 24)),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: Text(
                    widget.item.badgeCount! > 9 ? '9+' : '${widget.item.badgeCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(child: Icon(icon, color: iconColor, size: 24));
  }
}
