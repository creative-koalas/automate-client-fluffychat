import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HorizontalWheelScrollView extends StatefulWidget {
  final Widget child;
  final ScrollBehavior? scrollBehavior;
  final ScrollPhysics? physics;

  const HorizontalWheelScrollView({
    super.key,
    required this.child,
    this.scrollBehavior,
    this.physics,
  });

  @override
  State<HorizontalWheelScrollView> createState() =>
      _HorizontalWheelScrollViewState();
}

class _HorizontalWheelScrollViewState extends State<HorizontalWheelScrollView> {
  final ScrollController _scrollController = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;

    final targetOffset =
        (_scrollController.offset + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ).toDouble();

    if (targetOffset == _scrollController.offset) return;
    _scrollController.jumpTo(targetOffset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget scrollView = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: widget.physics,
      child: widget.child,
    );

    if (widget.scrollBehavior != null) {
      scrollView = ScrollConfiguration(
        behavior: widget.scrollBehavior!,
        child: scrollView,
      );
    }

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: scrollView,
    );
  }
}
