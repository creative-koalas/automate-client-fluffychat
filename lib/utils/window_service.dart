import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:psygo/utils/platform_infos.dart';

/// 窗口管理服务 - 用于 PC 端窗口样式切换和系统托盘
class WindowService with TrayListener {
  WindowService._();

  static final WindowService _instance = WindowService._();
  static WindowService get instance => _instance;

  static bool _trayInitialized = false;
  static _CloseInterceptor? _closeInterceptor;

  static const Size loginWindowSize = Size(420, 580);
  static const Size mainWindowSize = Size(1280, 720);
  // 最小宽度必须大于 PC 模式阈值 (columnWidth * 2 + navRailWidth = 840)
  static const Size mainWindowMinSize = Size(960, 600);

  /// 初始化系统托盘
  static Future<void> initSystemTray() async {
    if (!PlatformInfos.isDesktop || _trayInitialized) return;

    try {
      // 设置托盘图标
      String iconPath;
      if (Platform.isWindows) {
        iconPath = 'assets/logo.ico';
      } else if (Platform.isLinux) {
        iconPath = 'assets/logo.ico';
      } else {
        iconPath = 'assets/logo_opaque.png';
      }

      if (Platform.isLinux) {
        try {
          await trayManager.setIcon(iconPath);
        } catch (_) {
          iconPath = 'assets/logo_opaque.png';
          await trayManager.setIcon(iconPath);
        }
      } else {
        await trayManager.setIcon(iconPath);
      }

      // Linux 的 tray_manager 插件没有实现 setToolTip，只在 Windows/macOS 上调用
      if (!Platform.isLinux) {
        await trayManager.setToolTip('Psygo');
      }

      // 设置托盘菜单
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: '显示窗口',
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'exit',
              label: '退出',
            ),
          ],
        ),
      );

      // 添加托盘事件监听
      trayManager.addListener(_instance);
      _trayInitialized = true;
      debugPrint('[WindowService] System tray initialized');
    } catch (e) {
      debugPrint('[WindowService] Failed to init system tray: $e');
    }
  }

  /// 销毁系统托盘
  static Future<void> destroySystemTray() async {
    if (!PlatformInfos.isDesktop || !_trayInitialized) return;

    trayManager.removeListener(_instance);
    await trayManager.destroy();
    _trayInitialized = false;
  }

  // TrayListener 回调
  @override
  void onTrayIconMouseDown() {
    debugPrint('[WindowService] onTrayIconMouseDown');
    // 点击托盘图标显示窗口（仅 Windows 有效，Linux AppIndicator 不支持）
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    debugPrint('[WindowService] onTrayIconRightMouseDown');
    // 右键显示菜单（仅 Windows 需要，Linux AppIndicator 自动显示菜单）
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    debugPrint('[WindowService] onTrayMenuItemClick: ${menuItem.key}');
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'exit':
        exitApp();
        break;
    }
  }

  /// 显示窗口
  static Future<void> showWindow() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.show();
    await windowManager.focus();
  }

  /// 隐藏窗口到托盘
  static Future<void> hideToTray() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.hide();
  }

  /// 完全退出应用
  static Future<void> exitApp() async {
    if (!PlatformInfos.isDesktop) return;

    // 1. 先隐藏窗口，给用户即时反馈
    await windowManager.hide();

    // 2. 并行执行清理操作
    await Future.wait([
      destroySystemTray(),
      windowManager.setPreventClose(false),
    ]);

    // 3. 销毁窗口
    await windowManager.destroy();

    // 4. 给一点时间让异步操作完成
    await Future.delayed(const Duration(milliseconds: 100));

    // 5. 强制退出进程，确保不残留
    exit(0);
  }

  /// 设置关闭时隐藏到托盘（拦截系统关闭事件）
  static Future<void> setCloseToTray() async {
    if (!PlatformInfos.isDesktop) return;
    if (_closeInterceptor != null) return; // 避免重复添加

    await windowManager.setPreventClose(true);
    _closeInterceptor = _CloseInterceptor();
    windowManager.addListener(_closeInterceptor!);
  }

  /// 切换到主窗口模式（登录成功后调用）
  static Future<void> switchToMainWindow() async {
    if (!PlatformInfos.isDesktop) return;
    debugPrint('[WindowService] switchToMainWindow called');

    // 先解除大小限制，再设置新的大小
    await windowManager.setResizable(true);
    // 使用足够大的值代替 infinity（Windows 不支持 infinity）
    await windowManager.setMaximumSize(const Size(9999, 9999));
    await windowManager.setSize(mainWindowSize);
    // 设置最小大小（在设置完窗口大小后再设置）
    await windowManager.setMinimumSize(mainWindowMinSize);
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);

    // 主窗口关闭时隐藏到托盘
    await setCloseToTray();

    // 初始化系统托盘
    await initSystemTray();

    debugPrint('[WindowService] switchToMainWindow completed');
  }

  /// 切换到登录窗口模式
  static Future<void> switchToLoginWindow() async {
    if (!PlatformInfos.isDesktop) return;
    debugPrint('[WindowService] switchToLoginWindow called');

    await windowManager.setMinimumSize(loginWindowSize);
    await windowManager.setMaximumSize(loginWindowSize);
    await windowManager.setSize(loginWindowSize);
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setResizable(false);

    // 登录窗口也使用系统托盘
    await setCloseToTray();
    await initSystemTray();

    debugPrint('[WindowService] switchToLoginWindow completed');
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
    final defaultIconColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.5);
    final defaultHoverColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);

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
          onPressed: WindowService.hideToTray,  // 点击关闭时隐藏到托盘
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

/// 关闭事件拦截器 - 将关闭改为隐藏到托盘
class _CloseInterceptor with WindowListener {
  @override
  void onWindowClose() async {
    // 拦截关闭事件，改为隐藏到托盘
    await WindowService.hideToTray();
  }
}
