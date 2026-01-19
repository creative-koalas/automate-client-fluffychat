import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';

class TwoColumnLayout extends StatelessWidget {
  final Widget mainView;
  final Widget sideView;

  const TwoColumnLayout({
    super.key,
    required this.mainView,
    required this.sideView,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withAlpha(8),
                    blurRadius: 8,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
              width: FluffyThemes.columnWidth + FluffyThemes.navRailWidth,
              child: mainView,
            ),
            Container(
              width: 1.0,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.dividerColor.withAlpha(60),
                    theme.dividerColor,
                    theme.dividerColor.withAlpha(60),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                child: sideView,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
