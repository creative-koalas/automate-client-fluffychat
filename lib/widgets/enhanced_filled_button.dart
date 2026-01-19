import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';

/// Enhanced FilledButton with better tactile feedback and animations
class EnhancedFilledButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;
  final double? elevation;
  final BorderRadius? borderRadius;
  final bool useGradient;

  const EnhancedFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.elevation,
    this.borderRadius,
    this.useGradient = false,
  });

  const EnhancedFilledButton.icon({
    super.key,
    required this.onPressed,
    required this.child,
    required this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.elevation,
    this.borderRadius,
    this.useGradient = false,
  });

  @override
  State<EnhancedFilledButton> createState() => _EnhancedFilledButtonState();
}

class _EnhancedFilledButtonState extends State<EnhancedFilledButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FluffyThemes.durationInstant,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: FluffyThemes.curveSharp),
    );

    _elevationAnimation = Tween<double>(
      begin: FluffyThemes.elevationLg,
      end: FluffyThemes.elevationSm,
    ).animate(
      CurvedAnimation(parent: _controller, curve: FluffyThemes.curveSharp),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(FluffyThemes.radiusMd);
    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.primary;
    final foregroundColor =
        widget.foregroundColor ?? theme.colorScheme.onPrimary;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              gradient: widget.useGradient
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        backgroundColor,
                        backgroundColor.withValues(alpha: 0.85),
                      ],
                    )
                  : null,
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withValues(alpha: 0.3),
                  blurRadius: _elevationAnimation.value * 2,
                  offset: Offset(0, _elevationAnimation.value / 2),
                ),
              ],
            ),
            child: Material(
              color: widget.useGradient ? Colors.transparent : backgroundColor,
              borderRadius: borderRadius,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: borderRadius,
                splashColor: foregroundColor.withValues(alpha: 0.15),
                highlightColor: foregroundColor.withValues(alpha: 0.08),
                child: Container(
                  padding: widget.padding ??
                      const EdgeInsets.symmetric(
                        horizontal: FluffyThemes.spacing24,
                        vertical: FluffyThemes.spacing12,
                      ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          color: foregroundColor,
                          size: FluffyThemes.iconSizeSm,
                        ),
                        const SizedBox(width: FluffyThemes.spacing8),
                      ],
                      DefaultTextStyle(
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: FluffyThemes.fontSizeLg,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        child: widget.child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
