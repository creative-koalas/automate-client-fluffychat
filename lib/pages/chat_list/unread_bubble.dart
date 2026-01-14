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
        ? hasNotifications
            ? 20.0
            : 14.0
        : 0.0;

    // Calculate bubble width based on digit count
    final double bubbleWidth;
    if (!hasNotifications && !unread && !room.hasNewMessages) {
      bubbleWidth = 0;
    } else if (!hasNotifications) {
      bubbleWidth = 14.0; // Dot indicator
    } else {
      final digitCount = room.notificationCount.toString().length;
      if (digitCount == 1) {
        bubbleWidth = 20.0;
      } else if (digitCount == 2) {
        bubbleWidth = 28.0;
      } else {
        bubbleWidth = 36.0; // 3+ digits
      }
    }

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      height: unreadBubbleSize,
      width: bubbleWidth,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications || room.markedUnread
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(unreadBubbleSize / 2),
      ),
      child: hasNotifications
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: room.highlightCount > 0
                    ? theme.colorScheme.onError
                    : hasNotifications
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onPrimaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            )
          : const SizedBox.shrink(),
    );
  }
}
