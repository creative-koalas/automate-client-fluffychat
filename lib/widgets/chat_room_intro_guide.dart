import 'dart:math';

import 'package:flutter/material.dart';

class ChatRoomIntroGuideStep {
  final GlobalKey targetKey;
  final String title;
  final String? description;
  final WidgetBuilder? contentBuilder;

  const ChatRoomIntroGuideStep({
    required this.targetKey,
    required this.title,
    this.description,
    this.contentBuilder,
  });
}

class ChatRoomIntroGuide extends StatefulWidget {
  final bool visible;
  final GlobalKey containerKey;
  final List<ChatRoomIntroGuideStep> steps;
  final int currentStepIndex;
  final bool showStepCounter;
  final VoidCallback onPrimaryAction;
  final String primaryActionLabel;

  const ChatRoomIntroGuide({
    super.key,
    required this.visible,
    required this.containerKey,
    required this.steps,
    required this.currentStepIndex,
    this.showStepCounter = true,
    required this.onPrimaryAction,
    required this.primaryActionLabel,
  });

  @override
  State<ChatRoomIntroGuide> createState() => _ChatRoomIntroGuideState();
}

class _ChatRoomIntroGuideState extends State<ChatRoomIntroGuide> {
  static const double _guideBubbleWidth = 292;
  static const double _guideHighlightPadding = 10;
  static const double _guideScreenPadding = 16;
  static const double _guideCompactBubbleHeight = 218;
  static const double _guideExpandedBubbleHeight = 272;

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || widget.steps.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentStepIndex = widget.currentStepIndex.clamp(
      0,
      widget.steps.length - 1,
    );
    final currentStep = widget.steps[currentStepIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final targetRect = _resolveGuideTargetRect(currentStep.targetKey);
        if (targetRect == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.visible) {
              setState(() {});
            }
          });
          return const SizedBox.shrink();
        }

        final highlightRect = targetRect.inflate(_guideHighlightPadding);
        final bubbleSize = _resolveBubbleSize(
          Size(constraints.maxWidth, constraints.maxHeight),
          currentStep,
        );
        final bubbleLayout = _buildGuideBubbleLayout(
          Size(constraints.maxWidth, constraints.maxHeight),
          highlightRect,
          bubbleSize,
        );
        final theme = Theme.of(context);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ChatRoomGuideScrimPainter(
                    highlightRect: highlightRect,
                    color: Colors.black.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
            ..._buildGuideBlockerRegions(
              Size(constraints.maxWidth, constraints.maxHeight),
              highlightRect,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ChatRoomGuideConnectorPainter(
                    start: bubbleLayout.connectorStart,
                    end: bubbleLayout.connectorEnd,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
            Positioned(
              left: highlightRect.left,
              top: highlightRect.top,
              width: highlightRect.width,
              height: highlightRect.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.18),
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
              child: _buildGuideBubble(
                context: context,
                theme: theme,
                step: currentStep,
                currentStep: currentStepIndex + 1,
                totalSteps: widget.steps.length,
              ),
            ),
          ],
        );
      },
    );
  }

  Rect? _resolveGuideTargetRect(GlobalKey targetKey) {
    final targetContext = targetKey.currentContext;
    final containerContext = widget.containerKey.currentContext;
    if (targetContext == null || containerContext == null) {
      return null;
    }

    final targetBox = targetContext.findRenderObject();
    final containerBox = containerContext.findRenderObject();
    if (targetBox is! RenderBox ||
        containerBox is! RenderBox ||
        !targetBox.attached ||
        !containerBox.attached) {
      return null;
    }

    final origin = targetBox.localToGlobal(
      Offset.zero,
      ancestor: containerBox,
    );
    return origin & targetBox.size;
  }

  List<Widget> _buildGuideBlockerRegions(Size size, Rect highlightRect) {
    return [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: max(0.0, highlightRect.top),
        child: _buildGuideBlocker(),
      ),
      Positioned(
        left: 0,
        top: highlightRect.top,
        width: max(0.0, highlightRect.left),
        height: max(0.0, highlightRect.height),
        child: _buildGuideBlocker(),
      ),
      Positioned(
        left: highlightRect.right,
        top: highlightRect.top,
        width: max(0.0, size.width - highlightRect.right),
        height: max(0.0, highlightRect.height),
        child: _buildGuideBlocker(),
      ),
      Positioned(
        left: 0,
        top: highlightRect.bottom,
        right: 0,
        height: max(0.0, size.height - highlightRect.bottom),
        child: _buildGuideBlocker(),
      ),
    ];
  }

  Widget _buildGuideBlocker() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: const SizedBox.expand(),
    );
  }

  _ChatRoomGuideBubbleLayout _buildGuideBubbleLayout(
    Size size,
    Rect highlightRect,
    Size bubbleSize,
  ) {
    final bubbleWidth = bubbleSize.width;
    final bubbleHeight = bubbleSize.height;
    final spaceAbove =
        highlightRect.top - _guideScreenPadding - _guideConnectorGap;
    final spaceBelow =
        size.height - highlightRect.bottom - _guideScreenPadding - _guideConnectorGap;
    final showAbove = spaceAbove >= bubbleHeight
        ? true
        : (spaceBelow >= bubbleHeight ? false : spaceAbove > spaceBelow);
    final maxLeft = max(
      _guideScreenPadding,
      size.width - bubbleWidth - _guideScreenPadding,
    );
    final left = (highlightRect.center.dx - (bubbleWidth / 2))
        .clamp(_guideScreenPadding, maxLeft)
        .toDouble();
    final top = showAbove
        ? max(
            _guideScreenPadding,
            highlightRect.top - bubbleHeight - _guideConnectorGap,
          ).toDouble()
        : min(
            size.height - bubbleHeight - _guideScreenPadding,
            highlightRect.bottom + _guideConnectorGap,
          ).toDouble();
    final connectorX = highlightRect.center.dx
        .clamp(left + 28, left + bubbleWidth - 28)
        .toDouble();

    return _ChatRoomGuideBubbleLayout(
      left: left,
      top: top,
      connectorStart: Offset(
        connectorX,
        showAbove ? top + bubbleHeight : top,
      ),
      connectorEnd: Offset(
        highlightRect.center.dx,
        showAbove ? highlightRect.top : highlightRect.bottom,
      ),
    );
  }

  static const double _guideConnectorGap = 36;

  Size _resolveBubbleSize(Size availableSize, ChatRoomIntroGuideStep step) {
    final maxWidth = max(240.0, availableSize.width - (_guideScreenPadding * 2));
    final preferredWidth = availableSize.width >= 1280
        ? 560.0
        : (availableSize.width >= 900 ? 460.0 : _guideBubbleWidth);
    final width = min(preferredWidth, maxWidth);

    final preferredHeight = step.contentBuilder == null
        ? (availableSize.width >= 1280
            ? 320.0
            : (availableSize.width >= 900
                ? 276.0
                : _guideCompactBubbleHeight))
        : (availableSize.width >= 1280
            ? 440.0
            : (availableSize.width >= 900
                ? 372.0
                : _guideExpandedBubbleHeight));
    final height = min(
      preferredHeight,
      max(_guideCompactBubbleHeight, availableSize.height - (_guideScreenPadding * 2)),
    );

    return Size(width, height);
  }

  Widget _buildGuideBubble({
    required BuildContext context,
    required ThemeData theme,
    required ChatRoomIntroGuideStep step,
    required int currentStep,
    required int totalSteps,
  }) {
    final content =
        step.contentBuilder != null ? step.contentBuilder!(context) : null;
    final bodyChildren = <Widget>[
      if (step.description != null)
        Text(
          step.description!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF374151),
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      if (content != null) ...[
        if (step.description != null) const SizedBox(height: 14),
        content,
      ],
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
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
                    step.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                if (widget.showStepCounter)
                  Text(
                    '$currentStep/$totalSteps',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bodyChildren,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: widget.onPrimaryAction,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  widget.primaryActionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatRoomGuideBubbleLayout {
  final double left;
  final double top;
  final Offset connectorStart;
  final Offset connectorEnd;

  const _ChatRoomGuideBubbleLayout({
    required this.left,
    required this.top,
    required this.connectorStart,
    required this.connectorEnd,
  });
}

class _ChatRoomGuideScrimPainter extends CustomPainter {
  final Rect highlightRect;
  final Color color;

  const _ChatRoomGuideScrimPainter({
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
  bool shouldRepaint(covariant _ChatRoomGuideScrimPainter oldDelegate) =>
      oldDelegate.highlightRect != highlightRect || oldDelegate.color != color;
}

class _ChatRoomGuideConnectorPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  const _ChatRoomGuideConnectorPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vector = end - start;
    final distance = vector.distance;
    if (distance <= 0) return;

    final direction = vector / distance;
    final dotPaint = Paint()..color = color;
    const step = 10.0;

    for (double current = 0; current < distance; current += step) {
      final point = start + (direction * current);
      canvas.drawCircle(point, current == 0 ? 2.8 : 1.8, dotPaint);
    }

    canvas.drawCircle(end, 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _ChatRoomGuideConnectorPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.color != color;
}
