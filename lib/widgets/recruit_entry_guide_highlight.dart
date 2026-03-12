import 'dart:math';

import 'package:flutter/material.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/guide_bubble_layout.dart';

class RecruitEntryGuideHighlight extends StatefulWidget {
  final Widget child;
  final bool visible;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  const RecruitEntryGuideHighlight({
    super.key,
    required this.child,
    required this.visible,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
  });

  @override
  State<RecruitEntryGuideHighlight> createState() =>
      _RecruitEntryGuideHighlightState();
}

class _RecruitEntryGuideHighlightState
    extends State<RecruitEntryGuideHighlight> {
  static const double _guideBubbleWidth = 280;
  static const double _guideBubbleHeight = 176;
  static const double _guideHighlightPadding = 10;
  static const double _guideScreenPadding = 16;
  static const double _guideConnectorGap = 36;

  final GlobalKey _targetKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOverlayVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant RecruitEntryGuideHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _dismissed = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOverlayVisibility();
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOverlayVisibility();
    });
    return KeyedSubtree(
      key: _targetKey,
      child: widget.child,
    );
  }

  void _syncOverlayVisibility() {
    if (!mounted) return;

    final shouldShow = widget.visible && !_dismissed;
    if (!shouldShow) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry == null) {
      final overlay = Overlay.of(context, rootOverlay: true);
      _overlayEntry = OverlayEntry(builder: _buildOverlayEntry);
      overlay.insert(_overlayEntry!);
      return;
    }

    _overlayEntry!.markNeedsBuild();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _dismissOverlay() {
    if (_dismissed) return;
    setState(() {
      _dismissed = true;
    });
    _removeOverlay();
  }

  void _handleAction() {
    _dismissOverlay();
    widget.onAction?.call();
  }

  Widget _buildOverlayEntry(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scrimColor = theme.colorScheme.scrim.withValues(
      alpha: isDark ? 0.82 : 0.72,
    );
    final guideAccentColor = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.9 : 0.78,
    );
    final guideGlowColor = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.32 : 0.2,
    );
    final overlayState = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlayState.context.findRenderObject();
    final targetContext = _targetKey.currentContext;
    final targetBox = targetContext?.findRenderObject();
    if (overlayBox is! RenderBox ||
        targetBox is! RenderBox ||
        !overlayBox.attached ||
        !targetBox.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _overlayEntry?.markNeedsBuild();
      });
      return const SizedBox.shrink();
    }

    final targetOrigin = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetRect = targetOrigin & targetBox.size;
    final highlightRect = targetRect.inflate(_guideHighlightPadding);
    final overlaySize = overlayBox.size;
    final bubbleSize = _resolveGuideBubbleSize(
      availableSize: overlaySize,
      theme: theme,
      title: widget.title,
      description: widget.description,
    );
    final bubbleLayout = _buildGuideBubbleLayout(
      overlaySize,
      highlightRect,
      bubbleSize,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RecruitGuideScrimPainter(
                  highlightRect: highlightRect,
                  color: scrimColor,
                ),
              ),
            ),
          ),
          ..._buildDismissRegions(overlaySize, highlightRect),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RecruitGuideConnectorPainter(
                  start: bubbleLayout.connectorStart,
                  end: bubbleLayout.connectorEnd,
                  color: guideAccentColor,
                ),
              ),
            ),
          ),
          Positioned(
            left: highlightRect.left,
            top: highlightRect.top,
            width: highlightRect.width,
            height: highlightRect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleAction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: guideAccentColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: guideGlowColor,
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: bubbleLayout.left,
            top: bubbleLayout.top,
            width: bubbleSize.width,
            height: bubbleSize.height,
            child: _buildGuideBubble(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDismissRegions(Size size, Rect highlightRect) {
    return [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: max(0, highlightRect.top),
        child: _buildDismissRegion(),
      ),
      Positioned(
        left: 0,
        top: highlightRect.top,
        width: max(0, highlightRect.left),
        height: max(0, highlightRect.height),
        child: _buildDismissRegion(),
      ),
      Positioned(
        left: highlightRect.right,
        top: highlightRect.top,
        width: max(0, size.width - highlightRect.right),
        height: max(0, highlightRect.height),
        child: _buildDismissRegion(),
      ),
      Positioned(
        left: 0,
        top: highlightRect.bottom,
        right: 0,
        height: max(0, size.height - highlightRect.bottom),
        child: _buildDismissRegion(),
      ),
    ];
  }

  Widget _buildDismissRegion() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissOverlay,
      child: const SizedBox.expand(),
    );
  }

  GuideBubbleLayoutResult _buildGuideBubbleLayout(
    Size size,
    Rect highlightRect,
    Size bubbleSize,
  ) {
    return GuideBubbleLayoutResolver.resolve(
      containerSize: size,
      highlightRect: highlightRect,
      bubbleSize: bubbleSize,
      screenPadding: _guideScreenPadding,
      connectorGap: _guideConnectorGap,
      preferredPlacement: GuideBubblePlacement.above,
    );
  }

  Size _resolveGuideBubbleSize({
    required Size availableSize,
    required ThemeData theme,
    required String title,
    required String description,
  }) {
    final isDesktop = PlatformInfos.isDesktop;
    final maxWidth =
        max(240.0, availableSize.width - (_guideScreenPadding * 2));
    final preferredWidth = isDesktop ? 500.0 : _guideBubbleWidth;
    final width = min(preferredWidth, maxWidth);
    final titleColor = theme.colorScheme.onSurface;
    final bodyColor = theme.colorScheme.onSurfaceVariant;
    const horizontalPadding = 36.0;
    final titleWidth = max(120.0, width - horizontalPadding);
    final bodyWidth = max(120.0, width - horizontalPadding);
    final titleHeight = _measureGuideTextHeight(
      text: title,
      maxWidth: titleWidth,
      style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: titleColor,
          ) ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    );
    final bodyHeight = _measureGuideTextHeight(
      text: description,
      maxWidth: bodyWidth,
      style: theme.textTheme.bodyMedium?.copyWith(
            color: bodyColor,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ) ??
          const TextStyle(
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
    );
    final preferredHeight =
        18.0 + max(titleHeight, 22.0) + 14.0 + bodyHeight + 16.0 + 52.0 + 16.0;
    final minHeight = isDesktop ? 208.0 : _guideBubbleHeight;
    final maxHeight = max(
      minHeight,
      min(
        isDesktop ? 300.0 : 260.0,
        availableSize.height - (_guideScreenPadding * 2),
      ),
    );
    final height = preferredHeight.clamp(minHeight, maxHeight).toDouble();
    return Size(width, height);
  }

  double _measureGuideTextHeight({
    required String text,
    required double maxWidth,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  Widget _buildGuideBubble() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surface;
    final titleColor = theme.colorScheme.onSurface;
    final bodyColor = theme.colorScheme.onSurfaceVariant;
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.48 : 0.72,
    );
    final shadowColor = theme.colorScheme.shadow.withValues(
      alpha: isDark ? 0.34 : 0.18,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  widget.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: bodyColor,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: _handleAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    widget.actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecruitGuideScrimPainter extends CustomPainter {
  final Rect highlightRect;
  final Color color;

  const _RecruitGuideScrimPainter({
    required this.highlightRect,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final highlightPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          highlightRect,
          const Radius.circular(18),
        ),
      );
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      highlightPath,
    );

    canvas.drawPath(
      overlayPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RecruitGuideScrimPainter oldDelegate) =>
      oldDelegate.highlightRect != highlightRect || oldDelegate.color != color;
}

class _RecruitGuideConnectorPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  const _RecruitGuideConnectorPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) return;

    final direction = delta / distance;
    double currentDistance = 0;
    while (currentDistance < distance) {
      final segmentStart = start + direction * currentDistance;
      final segmentEnd =
          start + direction * min(currentDistance + dashWidth, distance);
      canvas.drawLine(segmentStart, segmentEnd, paint);
      currentDistance += dashWidth + dashSpace;
    }

    canvas.drawCircle(end, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RecruitGuideConnectorPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.color != color;
}
