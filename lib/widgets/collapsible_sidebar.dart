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
    final backgroundColor = widget.backgroundColor ?? theme.colorScheme.surface;
    final selectedColor = widget.selectedColor ??
        theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
    final hoverColor = widget.hoverColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.08);

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _widthAnimation,
          builder: (context, child) {
            return Container(
              width: _widthAnimation.value,
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
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

              const SizedBox(height: 8),

              // Menu items - 使用 AnimatedBuilder 监听动画，避免 setState
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) => _SidebarItem(
                    item: widget.items[index],
                    isSelected: index == widget.selectedIndex,
                    widthAnimation: _widthAnimation,
                    expandedWidth: widget.expandedWidth,
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
  final Color selectedColor;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.item,
    required this.isSelected,
    required this.widthAnimation,
    required this.expandedWidth,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? widget.selectedColor
                  : (_isHovered ? widget.hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedBuilder(
              animation: widget.widthAnimation,
              builder: (context, _) {
                // 根据动画进度决定显示模式
                final progress = (widget.widthAnimation.value - 72) / (widget.expandedWidth - 72);
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
          const SizedBox(width: 12),
          Icon(icon, color: iconColor, size: 24),
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
          if (widget.item.badgeCount != null && widget.item.badgeCount! > 0)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.item.badgeCount! > 99 ? '99+' : '${widget.item.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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
