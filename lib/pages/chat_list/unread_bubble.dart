import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;
  const UnreadBubble({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = room.isUnread;
    final hasNotifications = room.notificationCount > 0;
    final unreadBubbleSize = unread || room.hasNewMessages
        ? room.notificationCount > 0
            ? 22.0
            : 12.0
        : 0.0;

    // Calculate bubble width based on digit count (from dev/pc)
    final double bubbleWidth;
    if (!hasNotifications && !unread && !room.hasNewMessages) {
      bubbleWidth = 0;
    } else if (!hasNotifications) {
      bubbleWidth = 12.0; // Dot indicator
    } else {
      final digitCount = room.notificationCount.toString().length;
      if (digitCount == 1) {
        bubbleWidth = 22.0;
      } else if (digitCount == 2) {
        bubbleWidth = 30.0;
      } else {
        bubbleWidth = 38.0; // 3+ digits
      }
    }

    final isHighlight = room.highlightCount > 0;
    final bubbleColor = isHighlight
        ? theme.colorScheme.error
        : hasNotifications || room.markedUnread
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer;

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: hasNotifications ? 6 : 0),
      height: unreadBubbleSize,
      width: bubbleWidth,
      decoration: BoxDecoration(
        gradient: hasNotifications
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bubbleColor,
                  bubbleColor.withAlpha(220),
                ],
              )
            : null,
        color: hasNotifications ? null : bubbleColor,
        borderRadius: BorderRadius.circular(hasNotifications ? 11 : 6),
        boxShadow: hasNotifications
            ? [
                BoxShadow(
                  color: bubbleColor.withAlpha(80),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: hasNotifications
          ? Text(
              room.notificationCount > 99
                  ? '99+'
                  : room.notificationCount.toString(),
              style: TextStyle(
                color: isHighlight
                    ? theme.colorScheme.onError
                    : theme.colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            )
          : const SizedBox.shrink(),
    );
  }
}
