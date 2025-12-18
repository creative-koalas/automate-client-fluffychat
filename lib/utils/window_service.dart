import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:psygo/utils/platform_infos.dart';

/// 窗口管理服务 - 用于 PC 端窗口样式切换
class WindowService {
  WindowService._();

  static const Size loginWindowSize = Size(420, 580);
  static const Size mainWindowSize = Size(1280, 720);
  static const Size mainWindowMinSize = Size(800, 600);

  /// 切换到主窗口模式（登录成功后调用）
  static Future<void> switchToMainWindow() async {
    if (!PlatformInfos.isDesktop) return;
    debugPrint('[WindowService] switchToMainWindow called');

    // 先解除大小限制，再设置新的大小
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(mainWindowMinSize);
    // 使用足够大的值代替 infinity（Windows 不支持 infinity）
    await windowManager.setMaximumSize(const Size(9999, 9999));
    await windowManager.setSize(mainWindowSize);
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    debugPrint('[WindowService] switchToMainWindow completed');
  }

  /// 切换到登录窗口模式
  static Future<void> switchToLoginWindow() async {
    if (!PlatformInfos.isDesktop) return;

    await windowManager.setMinimumSize(loginWindowSize);
    await windowManager.setMaximumSize(loginWindowSize);
    await windowManager.setSize(loginWindowSize);
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setResizable(false);
  }

  /// 最小化窗口
  static Future<void> minimize() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.minimize();
  }

  /// 最大化窗口
  static Future<void> maximize() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.maximize();
  }

  /// 还原窗口（取消最大化）
  static Future<void> unmaximize() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.unmaximize();
  }

  /// 切换最大化状态
  static Future<void> toggleMaximize() async {
    if (!PlatformInfos.isDesktop) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 检查窗口是否最大化
  static Future<bool> isMaximized() async {
    if (!PlatformInfos.isDesktop) return false;
    return await windowManager.isMaximized();
  }

  /// 设置自定义窗口大小
  static Future<void> setCustomSize(Size size) async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.setSize(size);
    await windowManager.center();
  }

  /// 关闭窗口
  static Future<void> close() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.close();
  }
}

/// 自定义窗口控制按钮组件（最小化、最大化、关闭）
class WindowControlButtons extends StatefulWidget {
  final bool showMinimize;
  final bool showMaximize;
  final Color? iconColor;
  final Color? hoverColor;

  const WindowControlButtons({
    super.key,
    this.showMinimize = true,
    this.showMaximize = true,
    this.iconColor,
    this.hoverColor,
  });

  @override
  State<WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<WindowControlButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _initMaximizedState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initMaximizedState() async {
    final isMaximized = await WindowService.isMaximized();
    if (mounted) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.isDesktop) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.5);
    final defaultHoverColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showMinimize)
          _WindowButton(
            icon: Icons.remove,
            iconColor: widget.iconColor ?? defaultIconColor,
            hoverColor: widget.hoverColor ?? defaultHoverColor,
            onPressed: WindowService.minimize,
          ),
        if (widget.showMaximize)
          _WindowButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            iconColor: widget.iconColor ?? defaultIconColor,
            hoverColor: widget.hoverColor ?? defaultHoverColor,
            onPressed: WindowService.toggleMaximize,
          ),
        _WindowButton(
          icon: Icons.close,
          iconColor: widget.iconColor ?? defaultIconColor,
          hoverColor: const Color(0xFFE81123),
          hoverIconColor: Colors.white,
          onPressed: WindowService.close,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color hoverColor;
  final Color? hoverIconColor;
  final VoidCallback onPressed;

  const _WindowButton({
    required this.icon,
    required this.iconColor,
    required this.hoverColor,
    this.hoverIconColor,
    required this.onPressed,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered ? widget.hoverColor : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : widget.iconColor,
          ),
        ),
      ),
    );
  }
}

/// 可拖拽的窗口区域组件
class WindowDragArea extends StatelessWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.isDesktop) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }
}
