import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/unread_bubble.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/room_status_extension.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/hover_builder.dart';
import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

enum ArchivedRoomAction { delete, rejoin }

class ChatListItem extends StatelessWidget {
  final Room room;
  final Room? space;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = FluffyThemes.isColumnMode(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final unread = room.isUnread;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor =
        activeChat ? theme.colorScheme.secondaryContainer : null;
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender = lastEvent == null
        ? false
        : room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final space = this.space;

    final chatItem = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 3,
      ),
      child: AnimatedContainer(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: activeChat
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.18),
                    theme.colorScheme.tertiaryContainer.withValues(alpha: 0.12),
                  ],
                )
              : null,
          border: activeChat
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 1.5,
                )
              : null,
          boxShadow: activeChat
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: theme.colorScheme.shadow.withAlpha(10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.hardEdge,
          color: Colors.transparent,
          child: FutureBuilder(
            future: room.loadHeroUsers(),
            builder: (context, snapshot) => HoverBuilder(
              builder: (context, listTileHovered) => ListTile(
                visualDensity: const VisualDensity(vertical: 0),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              // 移动端用长按，PC端用右键（Listener处理）
              onLongPress: isDesktop ? null : () => onLongPress?.call(context),
              leading: HoverBuilder(
                builder: (context, hovered) => AnimatedScale(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  scale: hovered ? 1.1 : 1.0,
                  child: SizedBox(
                    width: Avatar.defaultSize,
                    height: Avatar.defaultSize,
                    child: Stack(
                      children: [
                        if (space != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Avatar(
                              border: BorderSide(
                                width: 2,
                                color: backgroundColor ??
                                    theme.colorScheme.surface,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 4,
                              ),
                              mxContent: space.avatar,
                              size: Avatar.defaultSize * 0.75,
                              name: space.getLocalizedDisplayname(),
                              onTap: () => onLongPress?.call(context),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Builder(
                            builder: (context) {
                              // 私聊时显示对方用户的头像
                              Uri? avatarUrl = room.avatar;
                              String avatarName = displayname;
                              if (directChatMatrixId != null) {
                                final user = room.unsafeGetUserFromMemoryOrFallback(directChatMatrixId);
                                avatarUrl = user.avatarUrl;
                                avatarName = user.calcDisplayname();
                              }
                              return Avatar(
                                border: space == null
                                    ? null
                                    : BorderSide(
                                        width: 2,
                                        color: backgroundColor ??
                                            theme.colorScheme.surface,
                                      ),
                                borderRadius: null,
                                mxContent: avatarUrl,
                                size: space != null
                                    ? Avatar.defaultSize * 0.75
                                    : Avatar.defaultSize,
                                name: avatarName,
                                presenceUserId: directChatMatrixId,
                                presenceBackgroundColor: backgroundColor,
                                onTap: () => onLongPress?.call(context),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => onLongPress?.call(context),
                            child: AnimatedScale(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              scale: listTileHovered ? 1.0 : 0.0,
                              child: Material(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(16),
                                child: const Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: unread || room.hasNewMessages
                            ? FontWeight.w500
                            : null,
                      ),
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(
                        Icons.notifications_off_outlined,
                        size: 16,
                      ),
                    ),
                  if (room.isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        room.latestEventReceivedTime
                            .localizedTimeShort(context),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (typingText.isEmpty &&
                      ownMessage &&
                      room.lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedSize(
                    clipBehavior: Clip.hardEdge,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: typingText.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: Icon(
                              Icons.edit_outlined,
                              color: theme.colorScheme.secondary,
                              size: 16,
                            ),
                          )
                        : room.lastEvent?.relationshipType ==
                                RelationshipTypes.thread
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius,
                                  ),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
                                margin: const EdgeInsets.only(right: 4.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.message_outlined,
                                      size: 12,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      L10n.of(context).thread,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: typingText.isNotEmpty
                        ? Text(
                                typingText,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                                maxLines: 1,
                                softWrap: false,
                              )
                            : FutureBuilder(
                                key: ValueKey(
                                  '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                                ),
                                future: needLastEventSender
                                    ? lastEvent.calcLocalizedBody(
                                        MatrixLocals(L10n.of(context)),
                                        hideReply: true,
                                        hideEdit: true,
                                        plaintextBody: true,
                                        removeMarkdown: true,
                                        withSenderNamePrefix: (!isDirectChat ||
                                            directChatMatrixId !=
                                                room.lastEvent?.senderId),
                                      )
                                    : null,
                                initialData:
                                    lastEvent?.calcLocalizedBodyFallback(
                                  MatrixLocals(L10n.of(context)),
                                  hideReply: true,
                                  hideEdit: true,
                                  plaintextBody: true,
                                  removeMarkdown: true,
                                  withSenderNamePrefix: (!isDirectChat ||
                                      directChatMatrixId !=
                                          room.lastEvent?.senderId),
                                ),
                                builder: (context, snapshot) => Text(
                                  room.membership == Membership.invite
                                      ? room
                                              .getState(
                                                EventTypes.RoomMember,
                                                room.client.userID!,
                                              )
                                              ?.content
                                              .tryGet<String>('reason') ??
                                          (isDirectChat
                                              ? L10n.of(context).newChatRequest
                                              : L10n.of(context)
                                                  .inviteGroupChat)
                                      : snapshot.data ??
                                          L10n.of(context).noMessagesYet,
                                  softWrap: false,
                                  maxLines: room.notificationCount >= 1 ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: unread || room.hasNewMessages
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.outline,
                                    decoration: room.lastEvent?.redacted == true
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                  ),
                  const SizedBox(width: 8),
                  UnreadBubble(room: room),
                ],
              ),
              onTap: onTap,
              trailing: onForget == null
                  ? room.membership == Membership.invite
                      ? IconButton(
                          tooltip: L10n.of(context).declineInvitation,
                          icon: const Icon(Icons.delete_forever_outlined),
                          color: theme.colorScheme.error,
                          onPressed: () async {
                            final consent = await showOkCancelAlertDialog(
                              context: context,
                              title: L10n.of(context).declineInvitation,
                              message: L10n.of(context).areYouSure,
                              okLabel: L10n.of(context).yes,
                              isDestructive: true,
                            );
                            if (consent != OkCancelResult.ok) return;
                            if (!context.mounted) return;
                            await showFutureLoadingDialog(
                              context: context,
                              future: room.leave,
                            );
                          },
                        )
                      : null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    // PC端使用Listener检测鼠标右键触发快捷菜单
    if (isDesktop) {
      return Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons == kSecondaryMouseButton) {
            onLongPress?.call(context);
          }
        },
        child: chatItem,
      );
    }

    return chatItem;
  }
}
