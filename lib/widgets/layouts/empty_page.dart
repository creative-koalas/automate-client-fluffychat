import 'dart:math';

import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';

class EmptyPage extends StatelessWidget {
  static const double _width = 400;
  const EmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = min(MediaQuery.sizeOf(context).width, EmptyPage._width) / 2.5;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.04),
              theme.colorScheme.surface,
              theme.colorScheme.secondaryContainer.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.0),
          duration: FluffyThemes.animationDurationSlow,
          curve: FluffyThemes.animationCurveBounce,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.scale(
              scale: value,
              child: child,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.12),
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.08),
                  theme.colorScheme.tertiaryContainer.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.5, 0.8, 1.0],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.08),
                    theme.colorScheme.tertiary.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: theme.colorScheme.shadow.withAlpha(15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.15),
                      theme.colorScheme.surfaceContainer.withValues(alpha: 0.1),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.05),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo_transparent.png',
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: width,
                  height: width,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
