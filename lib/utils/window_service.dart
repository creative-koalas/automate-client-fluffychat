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

    await windowManager.setMinimumSize(mainWindowMinSize);
    await windowManager.setMaximumSize(const Size(double.infinity, double.infinity));
    await windowManager.setSize(mainWindowSize);
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
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

  /// 关闭窗口
  static Future<void> close() async {
    if (!PlatformInfos.isDesktop) return;
    await windowManager.close();
  }
}

/// 自定义窗口控制按钮组件（关闭、最小化）
class WindowControlButtons extends StatelessWidget {
  final bool showMinimize;
  final Color? iconColor;
  final Color? hoverColor;

  const WindowControlButtons({
    super.key,
    this.showMinimize = true,
    this.iconColor,
    this.hoverColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.isDesktop) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.5);
    final defaultHoverColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMinimize)
          _WindowButton(
            icon: Icons.remove,
            iconColor: iconColor ?? defaultIconColor,
            hoverColor: hoverColor ?? defaultHoverColor,
            onPressed: WindowService.minimize,
          ),
        _WindowButton(
          icon: Icons.close,
          iconColor: iconColor ?? defaultIconColor,
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
