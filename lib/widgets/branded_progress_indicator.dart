import 'package:flutter/material.dart';

/// Branded circular progress indicator with gradient colors
class BrandedProgressIndicator extends StatelessWidget {
  final double? value;
  final double size;
  final double strokeWidth;
  final Color? backgroundColor;

  const BrandedProgressIndicator({
    super.key,
    this.value,
    this.size = 40,
    this.strokeWidth = 3.5,
    this.backgroundColor,
  });

  const BrandedProgressIndicator.small({
    super.key,
    this.value,
    this.backgroundColor,
  })  : size = 24,
        strokeWidth = 2.5;

  const BrandedProgressIndicator.large({
    super.key,
    this.value,
    this.backgroundColor,
  })  : size = 56,
        strokeWidth = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          if (backgroundColor != null || value != null)
            CircularProgressIndicator(
              value: value != null ? 1.0 : null,
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation<Color>(
                backgroundColor ??
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
          // Gradient foreground
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, opacity, child) => Opacity(
              opacity: opacity,
              child: child,
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.tertiary,
                ],
              ).createShader(bounds),
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: strokeWidth,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
