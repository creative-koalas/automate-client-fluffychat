import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;

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
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _widthAnimation = Tween<double>(
      begin: widget.collapsedWidth,
      end: widget.expandedWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent event) {
    if (!_isExpanded) {
      setState(() => _isExpanded = true);
      _animationController.forward();
    }
  }

  void _onExit(PointerEvent event) {
    // 当 preventCollapse 为 true 时（如弹出菜单打开时），不收缩侧边栏
    // 避免 widget 重建导致 PopupMenuButton.onSelected 不被调用
    if (_isExpanded && !widget.preventCollapse) {
      setState(() => _isExpanded = false);
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ?? theme.colorScheme.surface;
    final selectedColor = widget.selectedColor ??
        theme.colorScheme.primaryContainer.withOpacity(0.3);
    final hoverColor = widget.hoverColor ??
        theme.colorScheme.onSurface.withOpacity(0.08);

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: AnimatedBuilder(
        animation: _widthAnimation,
        builder: (context, child) {
          return Container(
            width: _widthAnimation.value,
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                right: BorderSide(
                  color: theme.dividerColor.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Header
                if (widget.header != null || widget.collapsedHeader != null)
                  _buildHeader(),

                const SizedBox(height: 8),

                // Menu items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      return _SidebarItem(
                        item: widget.items[index],
                        isSelected: index == widget.selectedIndex,
                        isExpanded: _isExpanded,
                        selectedColor: selectedColor,
                        hoverColor: hoverColor,
                        onTap: () {
                          widget.onItemSelected?.call(index);
                          widget.items[index].onTap?.call();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    // 始终使用同一个 header widget，让它自己根据宽度自适应
    // 避免 widget 切换导致 PopupMenuButton.onSelected 不被调用的问题
    return widget.header ?? const SizedBox(height: 60);
  }
}

class _SidebarItem extends StatefulWidget {
  final SidebarMenuItem item;
  final bool isSelected;
  final bool isExpanded;
  final Color selectedColor;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.item,
    required this.isSelected,
    required this.isExpanded,
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

    // 收缩状态下的图标（带角标）- 使用足够大的容器避免溢出
    final collapsedIconWidget = widget.item.badgeCount != null && widget.item.badgeCount! > 0
        ? SizedBox(
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
          )
        : Icon(icon, color: iconColor, size: 24);

    // 展开状态下的图标（不带角标，角标单独显示在右侧）
    final expandedIconWidget = Icon(icon, color: iconColor, size: 24);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 只有当宽度足够时才显示展开的 Row，避免动画过程中溢出
              final showExpanded = widget.isExpanded && constraints.maxWidth > 120;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 48,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? widget.selectedColor
                      : (_isHovered ? widget.hoverColor : Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: showExpanded
                    ? Row(
                        children: [
                          const SizedBox(width: 12),
                          expandedIconWidget,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.item.label,
                              style: TextStyle(
                                color: widget.isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                                fontWeight: widget.isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.item.badgeCount != null &&
                              widget.item.badgeCount! > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                widget.item.badgeCount! > 99
                                    ? '99+'
                                    : '${widget.item.badgeCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Center(child: collapsedIconWidget),
              );
            },
          ),
        ),
      ),
    );
  }
}
