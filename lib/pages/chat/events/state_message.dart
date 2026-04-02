import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/room_display_name.dart';
import '../../../config/app_config.dart';

class StateMessage extends StatelessWidget {
  final Event event;
  final void Function()? onExpand;
  final bool isCollapsed;
  const StateMessage(
    this.event, {
    this.onExpand,
    this.isCollapsed = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: isCollapsed
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    color: theme.colorScheme.surface.withAlpha(128),
                    borderRadius:
                        BorderRadius.circular(AppConfig.borderRadius / 3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _localizedBody(l10n),
                            ),
                            if (onExpand != null) ...[
                              const TextSpan(
                                text: ' + ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = onExpand,
                                text: l10n.moreEvents,
                              ),
                            ],
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12 * AppSettings.fontSizeFactor.value,
                          decoration: event.redacted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  String _localizedBody(L10n l10n) {
    final matrixLocals = MatrixLocals(l10n);
    switch (event.type) {
      case EventTypes.RoomMember:
        return _localizedRoomMemberBody(matrixLocals);
      case EventTypes.RoomPowerLevels:
        return matrixLocals.changedTheChatPermissions(
          _resolveDisplayName(event.senderId, matrixLocals),
        );
      case EventTypes.RoomName:
        return matrixLocals.changedTheChatNameTo(
          _resolveDisplayName(event.senderId, matrixLocals),
          event.content.tryGet<String>('name') ?? '',
        );
      case EventTypes.RoomTopic:
        return matrixLocals.changedTheChatDescriptionTo(
          _resolveDisplayName(event.senderId, matrixLocals),
          event.content.tryGet<String>('topic') ?? '',
        );
      case EventTypes.RoomAvatar:
        return matrixLocals.changedTheChatAvatar(
          _resolveDisplayName(event.senderId, matrixLocals),
        );
      default:
        return event.calcLocalizedBodyFallback(matrixLocals);
    }
  }

  String _localizedRoomMemberBody(MatrixLocals matrixLocals) {
    final targetName = _resolveDisplayName(event.stateKey, matrixLocals);
    final senderName = _resolveDisplayName(event.senderId, matrixLocals);
    final userIsTarget = event.stateKey == event.room.client.userID;
    final userIsSender = event.senderId == event.room.client.userID;

    switch (event.roomMemberChangeType) {
      case RoomMemberChangeType.avatar:
        return matrixLocals.changedTheProfileAvatar(targetName);
      case RoomMemberChangeType.displayname:
        final newDisplayname =
            event.content.tryGet<String>('displayname') ?? '';
        final oldDisplayname =
            event.prevContent?.tryGet<String>('displayname') ?? '';
        return matrixLocals.changedTheDisplaynameTo(
          oldDisplayname,
          newDisplayname,
        );
      case RoomMemberChangeType.join:
        return userIsTarget
            ? matrixLocals.youJoinedTheChat
            : matrixLocals.joinedTheChat(targetName);
      case RoomMemberChangeType.acceptInvite:
        return userIsTarget
            ? matrixLocals.youAcceptedTheInvitation
            : matrixLocals.acceptedTheInvitation(targetName);
      case RoomMemberChangeType.rejectInvite:
        return userIsTarget
            ? matrixLocals.youRejectedTheInvitation
            : matrixLocals.rejectedTheInvitation(targetName);
      case RoomMemberChangeType.withdrawInvitation:
        return userIsSender
            ? matrixLocals.youHaveWithdrawnTheInvitationFor(targetName)
            : matrixLocals.hasWithdrawnTheInvitationFor(
                senderName,
                targetName,
              );
      case RoomMemberChangeType.leave:
        return matrixLocals.userLeftTheChat(targetName);
      case RoomMemberChangeType.kick:
        return userIsSender
            ? matrixLocals.youKicked(targetName)
            : matrixLocals.kicked(senderName, targetName);
      case RoomMemberChangeType.invite:
        return userIsSender
            ? matrixLocals.youInvitedUser(targetName)
            : userIsTarget
                ? matrixLocals.youInvitedBy(senderName)
                : matrixLocals.invitedUser(senderName, targetName);
      case RoomMemberChangeType.ban:
        return userIsSender
            ? matrixLocals.youBannedUser(targetName)
            : matrixLocals.bannedUser(senderName, targetName);
      case RoomMemberChangeType.unban:
        return userIsSender
            ? matrixLocals.youUnbannedUser(targetName)
            : matrixLocals.unbannedUser(senderName, targetName);
      case RoomMemberChangeType.knock:
        return matrixLocals.hasKnocked(targetName);
      case RoomMemberChangeType.other:
        return userIsTarget
            ? matrixLocals.youJoinedTheChat
            : matrixLocals.joinedTheChat(targetName);
    }
  }

  String _resolveDisplayName(
    String? matrixUserId,
    MatrixLocals matrixLocals,
  ) {
    return resolveDisplayNameForMatrixUserId(
      room: event.room,
      matrixUserId: matrixUserId,
      matrixLocals: matrixLocals,
    );
  }
}
