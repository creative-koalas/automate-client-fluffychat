import 'package:flutter/material.dart';

import 'package:badges/badges.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/widgets/hover_builder.dart';
import 'package:psygo/widgets/unread_rooms_badge.dart';
import '../../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderRadius = BorderRadius.circular(14);
    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final unreadBadgeFilter = this.unreadBadgeFilter;
    return HoverBuilder(
      builder: (context, hovered) {
        return SizedBox(
          height: 72,
          width: FluffyThemes.navRailWidth,
          child: Stack(
            children: [
              Positioned(
                top: 8,
                bottom: 8,
                left: 0,
                child: AnimatedContainer(
                  width: isSelected
                      ? FluffyThemes.isColumnMode(context)
                          ? 6
                          : 4
                      : 0,
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(90),
                      bottomRight: Radius.circular(90),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(60),
                              blurRadius: 8,
                              offset: const Offset(2, 0),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Center(
                child: AnimatedScale(
                  scale: hovered ? 1.08 : 1.0,
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  child: AnimatedContainer(
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.primary.withAlpha(30),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Material(
                      borderRadius: borderRadius,
                      color: isSelected
                          ? theme.colorScheme.primaryContainer
                          : hovered
                              ? theme.colorScheme.surfaceContainerHighest
                              : theme.colorScheme.surfaceContainerHigh,
                      child: Tooltip(
                        message: toolTip,
                        child: InkWell(
                          borderRadius: borderRadius,
                          splashColor: theme.colorScheme.primary.withAlpha(30),
                          highlightColor: theme.colorScheme.primary.withAlpha(15),
                          onTap: onTap,
                          child: unreadBadgeFilter == null
                              ? icon
                              : UnreadRoomsBadge(
                                  filter: unreadBadgeFilter,
                                  badgePosition: BadgePosition.topEnd(
                                    top: -12,
                                    end: -8,
                                  ),
                                  child: icon,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
