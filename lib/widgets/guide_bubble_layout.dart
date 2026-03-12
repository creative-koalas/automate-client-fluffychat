import 'dart:math';

import 'package:flutter/material.dart';

enum GuideBubblePlacement {
  above,
  below,
  left,
  right,
}

class GuideBubbleLayoutResult {
  final double left;
  final double top;
  final Offset connectorStart;
  final Offset connectorEnd;

  const GuideBubbleLayoutResult({
    required this.left,
    required this.top,
    required this.connectorStart,
    required this.connectorEnd,
  });
}

class GuideBubbleLayoutResolver {
  static GuideBubbleLayoutResult resolve({
    required Size containerSize,
    required Rect highlightRect,
    required Size bubbleSize,
    required double screenPadding,
    required double connectorGap,
    required GuideBubblePlacement preferredPlacement,
    Offset bubbleOffset = Offset.zero,
  }) {
    final bounds = Rect.fromLTWH(
      screenPadding,
      screenPadding,
      max(0, containerSize.width - (screenPadding * 2)),
      max(0, containerSize.height - (screenPadding * 2)),
    );
    final placements = _fallbackOrder(preferredPlacement);
    _GuideBubbleCandidate? bestCandidate;

    for (var i = 0; i < placements.length; i++) {
      final candidate = _buildCandidate(
        placement: placements[i],
        highlightRect: highlightRect,
        bubbleSize: bubbleSize,
        bounds: bounds,
        order: i,
        connectorGap: connectorGap,
        bubbleOffset: bubbleOffset,
      );
      if (candidate.fitsNaturally) {
        return candidate.layout;
      }
      if (bestCandidate == null || candidate.score < bestCandidate.score) {
        bestCandidate = candidate;
      }
    }

    return bestCandidate!.layout;
  }

  static _GuideBubbleCandidate _buildCandidate({
    required GuideBubblePlacement placement,
    required Rect highlightRect,
    required Size bubbleSize,
    required Rect bounds,
    required int order,
    required double connectorGap,
    required Offset bubbleOffset,
  }) {
    final rawOffset = _rawBubbleOffset(
      placement: placement,
      highlightRect: highlightRect,
      bubbleSize: bubbleSize,
      connectorGap: connectorGap,
    ).translate(bubbleOffset.dx, bubbleOffset.dy);
    final maxLeft = max(bounds.left, bounds.right - bubbleSize.width);
    final maxTop = max(bounds.top, bounds.bottom - bubbleSize.height);
    final left = rawOffset.dx.clamp(bounds.left, maxLeft).toDouble();
    final top = rawOffset.dy.clamp(bounds.top, maxTop).toDouble();
    final bubbleRect = Rect.fromLTWH(
      left,
      top,
      bubbleSize.width,
      bubbleSize.height,
    );
    final fitsNaturally =
        (left - rawOffset.dx).abs() < 0.5 && (top - rawOffset.dy).abs() < 0.5;
    final shiftDistance =
        (left - rawOffset.dx).abs() + (top - rawOffset.dy).abs();

    return _GuideBubbleCandidate(
      layout: GuideBubbleLayoutResult(
        left: left,
        top: top,
        connectorStart: _connectorStart(
          placement: placement,
          bubbleRect: bubbleRect,
          targetRect: highlightRect,
        ),
        connectorEnd: _connectorEnd(
          placement: placement,
          targetRect: highlightRect,
          bubbleRect: bubbleRect,
        ),
      ),
      fitsNaturally: fitsNaturally,
      score: (shiftDistance * 10) + (order * 1000),
    );
  }

  static Offset _rawBubbleOffset({
    required GuideBubblePlacement placement,
    required Rect highlightRect,
    required Size bubbleSize,
    required double connectorGap,
  }) {
    switch (placement) {
      case GuideBubblePlacement.above:
        return Offset(
          highlightRect.center.dx - (bubbleSize.width / 2),
          highlightRect.top - bubbleSize.height - connectorGap,
        );
      case GuideBubblePlacement.below:
        return Offset(
          highlightRect.center.dx - (bubbleSize.width / 2),
          highlightRect.bottom + connectorGap,
        );
      case GuideBubblePlacement.left:
        return Offset(
          highlightRect.left - bubbleSize.width - connectorGap,
          highlightRect.center.dy - (bubbleSize.height / 2),
        );
      case GuideBubblePlacement.right:
        return Offset(
          highlightRect.right + connectorGap,
          highlightRect.center.dy - (bubbleSize.height / 2),
        );
    }
  }

  static Offset _connectorStart({
    required GuideBubblePlacement placement,
    required Rect bubbleRect,
    required Rect targetRect,
  }) {
    switch (placement) {
      case GuideBubblePlacement.above:
        return Offset(
          targetRect.center.dx
              .clamp(bubbleRect.left + 28, bubbleRect.right - 28)
              .toDouble(),
          bubbleRect.bottom,
        );
      case GuideBubblePlacement.below:
        return Offset(
          targetRect.center.dx
              .clamp(bubbleRect.left + 28, bubbleRect.right - 28)
              .toDouble(),
          bubbleRect.top,
        );
      case GuideBubblePlacement.left:
        return Offset(
          bubbleRect.right,
          targetRect.center.dy
              .clamp(bubbleRect.top + 28, bubbleRect.bottom - 28)
              .toDouble(),
        );
      case GuideBubblePlacement.right:
        return Offset(
          bubbleRect.left,
          targetRect.center.dy
              .clamp(bubbleRect.top + 28, bubbleRect.bottom - 28)
              .toDouble(),
        );
    }
  }

  static Offset _connectorEnd({
    required GuideBubblePlacement placement,
    required Rect targetRect,
    required Rect bubbleRect,
  }) {
    switch (placement) {
      case GuideBubblePlacement.above:
        return Offset(
          bubbleRect.center.dx
              .clamp(targetRect.left + 8, targetRect.right - 8)
              .toDouble(),
          targetRect.top,
        );
      case GuideBubblePlacement.below:
        return Offset(
          bubbleRect.center.dx
              .clamp(targetRect.left + 8, targetRect.right - 8)
              .toDouble(),
          targetRect.bottom,
        );
      case GuideBubblePlacement.left:
        return Offset(
          targetRect.left,
          bubbleRect.center.dy
              .clamp(targetRect.top + 8, targetRect.bottom - 8)
              .toDouble(),
        );
      case GuideBubblePlacement.right:
        return Offset(
          targetRect.right,
          bubbleRect.center.dy
              .clamp(targetRect.top + 8, targetRect.bottom - 8)
              .toDouble(),
        );
    }
  }

  static List<GuideBubblePlacement> _fallbackOrder(
    GuideBubblePlacement preferredPlacement,
  ) {
    switch (preferredPlacement) {
      case GuideBubblePlacement.above:
        return const [
          GuideBubblePlacement.above,
          GuideBubblePlacement.below,
          GuideBubblePlacement.right,
          GuideBubblePlacement.left,
        ];
      case GuideBubblePlacement.below:
        return const [
          GuideBubblePlacement.below,
          GuideBubblePlacement.above,
          GuideBubblePlacement.right,
          GuideBubblePlacement.left,
        ];
      case GuideBubblePlacement.left:
        return const [
          GuideBubblePlacement.left,
          GuideBubblePlacement.right,
          GuideBubblePlacement.below,
          GuideBubblePlacement.above,
        ];
      case GuideBubblePlacement.right:
        return const [
          GuideBubblePlacement.right,
          GuideBubblePlacement.left,
          GuideBubblePlacement.below,
          GuideBubblePlacement.above,
        ];
    }
  }
}

class _GuideBubbleCandidate {
  final GuideBubbleLayoutResult layout;
  final bool fitsNaturally;
  final double score;

  const _GuideBubbleCandidate({
    required this.layout,
    required this.fitsNaturally,
    required this.score,
  });
}
