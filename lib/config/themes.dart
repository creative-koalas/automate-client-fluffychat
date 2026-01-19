import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:psygo/config/setting_keys.dart';

abstract class FluffyThemes {
  // ============================================================================
  // 🎨 Design Tokens - 统一的设计系统
  // ============================================================================

  // 📐 布局尺寸
  static const double columnWidth = 380.0;
  static const double maxTimelineWidth = columnWidth * 2;
  static const double navRailWidth = 80.0;

  // 📏 间距系统 (4px 基准)
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;

  // 🔘 圆角系统 (统一为 4 的倍数)
  static const double radiusXs = 4.0;   // 超小圆角 (Chip, Tag)
  static const double radiusSm = 8.0;   // 小圆角 (TextButton)
  static const double radiusMd = 12.0;  // 中圆角 (Button, ListTile)
  static const double radiusLg = 16.0;  // 大圆角 (Card, Avatar)
  static const double radiusXl = 20.0;  // 超大圆角 (Dialog, BottomSheet)
  static const double radiusFull = 999.0; // 完全圆形

  // 🎭 阴影层级系统
  static const double elevationNone = 0.0;
  static const double elevationXs = 1.0;
  static const double elevationSm = 2.0;
  static const double elevationMd = 4.0;
  static const double elevationLg = 8.0;
  static const double elevationXl = 16.0;

  // ⏱️ 动画时长系统
  static const Duration durationInstant = Duration(milliseconds: 100);
  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 400);
  static const Duration durationSlower = Duration(milliseconds: 600);

  // 📈 动画曲线系统
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveBounce = Curves.easeOutBack;
  static const Curve curveSmooth = Curves.easeInOutCubic;
  static const Curve curveSharp = Curves.easeOut;

  // 🔤 字体大小系统
  static const double fontSizeXs = 11.0;
  static const double fontSizeSm = 12.0;
  static const double fontSizeMd = 14.0;
  static const double fontSizeLg = 16.0;
  static const double fontSizeXl = 18.0;
  static const double fontSize2xl = 20.0;
  static const double fontSize3xl = 24.0;
  static const double fontSize4xl = 32.0;

  // 🎯 图标大小系统
  static const double iconSizeXs = 16.0;
  static const double iconSizeSm = 20.0;
  static const double iconSizeMd = 24.0;
  static const double iconSizeLg = 32.0;
  static const double iconSizeXl = 48.0;

  // ============================================================================
  // 🛠️ 工具方法
  // ============================================================================

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  // 🌈 渐变背景生成器 (优化版 - 支持自定义方向)
  static LinearGradient backgroundGradient(
    BuildContext context, {
    int alpha = 255,
    AlignmentGeometry begin = Alignment.topCenter,
    AlignmentGeometry end = Alignment.bottomCenter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  // 🎨 双色渐变生成器 (新增 - 更简洁的渐变)
  static LinearGradient simpleGradient(
    BuildContext context, {
    int alpha = 255,
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
      ],
    );
  }

  // 🌑 阴影生成器 - 多层级系统
  static List<BoxShadow> shadow(
    BuildContext context, {
    double elevation = elevationMd,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 根据 elevation 计算阴影参数
    final blurRadius = elevation * 2;
    final offsetY = elevation / 2;
    final alpha = isDark ? (elevation * 5).toInt() : (elevation * 3).toInt();

    return [
      BoxShadow(
        color: Colors.black.withAlpha(alpha.clamp(0, 255)),
        blurRadius: blurRadius,
        offset: Offset(0, offsetY),
        spreadRadius: 0,
      ),
    ];
  }

  // 🎭 多层阴影生成器 (新增 - 更立体的效果)
  static List<BoxShadow> layeredShadow(
    BuildContext context, {
    double elevation = elevationMd,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseAlpha = isDark ? 40 : 20;

    return [
      // 主阴影 (柔和扩散)
      BoxShadow(
        color: Colors.black.withAlpha(baseAlpha),
        blurRadius: elevation * 2,
        offset: Offset(0, elevation / 2),
        spreadRadius: 0,
      ),
      // 次阴影 (增强深度)
      BoxShadow(
        color: Colors.black.withAlpha((baseAlpha * 0.5).toInt()),
        blurRadius: elevation,
        offset: Offset(0, elevation / 4),
        spreadRadius: -elevation / 4,
      ),
    ];
  }

  // 保留旧 API 兼容性
  @Deprecated('Use shadow(context, elevation: elevationMd) instead')
  static List<BoxShadow> cardShadow(BuildContext context) =>
      shadow(context, elevation: elevationMd);

  @Deprecated('Use shadow(context, elevation: elevationLg) instead')
  static List<BoxShadow> elevatedShadow(BuildContext context) =>
      shadow(context, elevation: elevationLg);

  // 优化后的动画配置 - 保留旧 API 兼容性
  @Deprecated('Use durationFast instead')
  static const Duration animationDuration = durationFast;

  @Deprecated('Use durationSlow instead')
  static const Duration animationDurationSlow = durationSlow;

  @Deprecated('Use curveStandard instead')
  static const Curve animationCurve = curveStandard;

  @Deprecated('Use curveBounce instead')
  static const Curve animationCurveBounce = curveBounce;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: seed ?? Color(AppSettings.colorSchemeSeedInt.value),
    );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Windows 平台使用微软雅黑，解决中文字体粗细不一致问题
      fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
      dividerColor: brightness == Brightness.dark
          ? colorScheme.surfaceContainerHighest
          : colorScheme.surfaceContainer,
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        iconColor: colorScheme.onSurface,
        textStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        contentPadding: const EdgeInsets.all(spacing12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainerHigh.withAlpha(100),
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: spacing12, vertical: spacing8),
        labelPadding: const EdgeInsets.symmetric(horizontal: spacing4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        labelStyle: const TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
        ).copyWith(color: colorScheme.onSurfaceVariant),
        secondaryLabelStyle: const TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w600,
        ).copyWith(color: colorScheme.onPrimaryContainer),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        shadowColor:
            isColumnMode ? colorScheme.surfaceContainer.withAlpha(128) : null,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isColumnMode ? colorScheme.surface : null,
        actionsPadding:
            isColumnMode ? const EdgeInsets.symmetric(horizontal: 16.0) : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            width: 1,
            color: colorScheme.primary,
          ),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        showCloseIcon: isColumnMode,
        behavior: SnackBarBehavior.floating,
        width: isColumnMode ? FluffyThemes.columnWidth * 1.5 : null,
        backgroundColor: colorScheme.inverseSurface,
        actionTextColor: colorScheme.inversePrimary,
        contentTextStyle: const TextStyle(
          fontSize: fontSizeMd,
          fontWeight: FontWeight.w500,
        ).copyWith(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        elevation: elevationMd,
        insetPadding: const EdgeInsets.all(spacing16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: elevationNone,
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          textStyle: const TextStyle(
            fontSize: fontSizeLg,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      // 填充按钮样式
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          textStyle: const TextStyle(
            fontSize: fontSizeLg,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      // 文字按钮样式
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing8),
          textStyle: const TextStyle(
            fontSize: fontSizeMd,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      // 图标按钮样式
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(spacing8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      // 卡片样式
      cardTheme: CardThemeData(
        elevation: elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      // 列表瓦片样式
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing4),
      ),
      // 对话框样式
      dialogTheme: DialogThemeData(
        elevation: elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        backgroundColor: colorScheme.surface,
      ),
      // 底部表样式
      bottomSheetTheme: BottomSheetThemeData(
        elevation: elevationNone,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        backgroundColor: colorScheme.surface,
        dragHandleColor: colorScheme.onSurfaceVariant.withAlpha(80),
        dragHandleSize: const Size(spacing40, spacing4),
        showDragHandle: true,
      ),
      // 浮动按钮样式
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: elevationSm,
        highlightElevation: elevationMd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      // 导航栏样式
      navigationBarTheme: NavigationBarThemeData(
        elevation: elevationNone,
        height: 72,
        indicatorColor: colorScheme.primaryContainer.withAlpha(180),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: fontSizeSm,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            );
          }
          return TextStyle(
            fontSize: fontSizeSm,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              size: iconSizeMd,
              color: colorScheme.primary,
            );
          }
          return IconThemeData(
            size: iconSizeMd,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => brightness == Brightness.light
      ? colorScheme.primary
      : colorScheme.primaryContainer;

  Color get onBubbleColor => brightness == Brightness.light
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  Color get secondaryBubbleColor => HSLColor.fromColor(
        brightness == Brightness.light
            ? colorScheme.tertiary
            : colorScheme.tertiaryContainer,
      ).withSaturation(0.5).toColor();
}
