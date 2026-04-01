import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/unread_bubble.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/chat_list_preview_sender_name.dart';
import 'package:psygo/utils/matrix_mention_display_name.dart';
import 'package:psygo/utils/matrix_sdk_extensions/agent_presentation_extension.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/room_status_extension.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/hover_builder.dart';
import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

enum ArchivedRoomAction { delete, rejoin }

class ChatListItem extends StatefulWidget {
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
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  Room get room => widget.room;
  Room? get space => widget.space;
  bool get activeChat => widget.activeChat;
  void Function(BuildContext context)? get onLongPress => widget.onLongPress;
  void Function()? get onForget => widget.onForget;
  void Function() get onTap => widget.onTap;
  String? get filter => widget.filter;

  @override
  void initState() {
    super.initState();
    // 监听 AgentService 变化，员工数据加载完成后刷新头像
    AgentService.instance.agentsNotifier.addListener(_onAgentsChanged);
    AgentService.instance.profileNotifier.addListener(_onAgentsChanged);
  }

  @override
  void dispose() {
    AgentService.instance.agentsNotifier.removeListener(_onAgentsChanged);
    AgentService.instance.profileNotifier.removeListener(_onAgentsChanged);
    super.dispose();
  }

  void _onAgentsChanged() {
    if (mounted) setState(() {});
  }

  String _resolveDisplayNameForMatrixUserId({
    required String? matrixUserId,
    required MatrixLocals matrixLocals,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return '';
    }
    final user = room.unsafeGetUserFromMemoryOrFallback(key);
    AgentService.instance.ensureMatrixProfilePresentationById(
      client: room.client,
      matrixUserId: key,
      fallbackDisplayName:
          user.displayName ?? user.calcDisplayname(i18n: matrixLocals),
      fallbackAvatarUri: user.avatarUrl,
    );
    if (!room.isDirectChat) {
      AgentService.instance.ensureGroupDisplayNameByMatrixUserId(key);
      final groupDisplayName =
          AgentService.instance.tryResolveGroupDisplayNameByMatrixUserId(key);
      if (groupDisplayName != null) {
        return groupDisplayName;
      }
    }
    return AgentService.instance.resolveDisplayNameByMatrixUserId(
      key,
      fallbackDisplayName: user.calcDisplayname(i18n: matrixLocals),
    );
  }

  String _resolveRoomDisplayName(BuildContext context) {
    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final directChatMatrixId = room.directChatMatrixID;

    if (directChatMatrixId != null) {
      return _resolveDisplayNameForMatrixUserId(
        matrixUserId: directChatMatrixId,
        matrixLocals: matrixLocals,
      );
    }

    if (room.name.isNotEmpty) {
      return room.name;
    }

    final canonicalAlias = room.canonicalAlias.localpart;
    if (canonicalAlias != null && canonicalAlias.isNotEmpty) {
      return canonicalAlias;
    }

    final heroIds = <String>[...?room.summary.mHeroes];

    final names = <String>[];
    for (final heroId in heroIds) {
      if (heroId.isEmpty || heroId == room.client.userID) {
        continue;
      }
      final resolvedName = _resolveDisplayNameForMatrixUserId(
        matrixUserId: heroId,
        matrixLocals: matrixLocals,
      ).trim();
      if (resolvedName.isNotEmpty) {
        names.add(resolvedName);
      }
    }

    if (names.isNotEmpty) {
      final joinedNames = names.join(', ');
      if (room.isAbandonedDMRoom) {
        return l10n.wasDirectChatDisplayName(joinedNames);
      }
      return room.isDirectChat ? joinedNames : l10n.groupWith(joinedNames);
    }

    return room.getLocalizedDisplayname(matrixLocals);
  }
  bool _usesSenderNamePrefix({
    required Event? lastEvent,
    required bool isDirectChat,
    required String? directChatMatrixId,
  }) {
    if (lastEvent == null) {
      return false;
    }
    return !isDirectChat || directChatMatrixId != lastEvent.senderId;
  }

  String _renderSubtitleText(
    BuildContext context,
    String subtitleText, {
    required Event? lastEvent,
    required bool isDirectChat,
    required String? directChatMatrixId,
  }) {
    final normalizedText = _replaceOwnAgentSenderPrefix(
      context,
      subtitleText,
      lastEvent: lastEvent,
      isDirectChat: isDirectChat,
      directChatMatrixId: directChatMatrixId,
    );
    return renderMatrixMentionsWithDisplayName(
      text: normalizedText,
      room: room,
    );
  }

  String _replaceOwnAgentSenderPrefix(
    BuildContext context,
    String previewText, {
    required Event? lastEvent,
    required bool isDirectChat,
    required String? directChatMatrixId,
  }) {
    if (!_usesSenderNamePrefix(
      lastEvent: lastEvent,
      isDirectChat: isDirectChat,
      directChatMatrixId: directChatMatrixId,
    )) {
      return previewText;
    }
    if (lastEvent == null ||
        lastEvent.senderId == room.client.userID ||
        lastEvent.type != EventTypes.Message ||
        !Event.textOnlyMessageTypes.contains(lastEvent.messageType)) {
      return previewText;
    }

    final agent = AgentService.instance.getAgentByMatrixUserId(
      lastEvent.senderId,
    );
    final resolvedSenderName = agent?.displayName.trim() ?? '';
    if (resolvedSenderName.isEmpty) {
      return previewText;
    }

    final originalSenderName = lastEvent.senderFromMemoryOrFallback
        .calcDisplayname(i18n: MatrixLocals(L10n.of(context)));
    return replaceLocalizedSenderPrefix(
      text: previewText,
      originalSenderName: originalSenderName,
      resolvedSenderName: resolvedSenderName,
    );
  }

  Widget _buildEmployeeAvatar({
    required String avatarUrl,
    required String name,
    required double size,
    BorderSide? border,
    Color? presenceBackgroundColor,
    Color? statusDotColor,
    void Function()? onTap,
  }) {
    final avatarUri = AgentService.instance.parseAvatarUri(avatarUrl);
    return Avatar(
      border: border,
      borderRadius: null,
      mxContent: avatarUri,
      size: size,
      name: name,
      presenceBackgroundColor: presenceBackgroundColor,
      statusDotColor: statusDotColor,
      onTap: onTap,
    );
  }

  Color _employeeWorkStatusColor(String status) {
    switch (status) {
      case 'working':
        return Colors.green;
      case 'slacking':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = FluffyThemes.isColumnMode(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final rawLastEvent = room.lastEvent;
    final isRefreshingLastEvent =
        rawLastEvent?.type == EventTypes.refreshingLastEvent;
    final lastEvent = isRefreshingLastEvent ? null : rawLastEvent;
    final lastEventSenderId = lastEvent?.senderId;
    final ownMessage = lastEventSenderId == room.client.userID;
    final unread = room.isUnread;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : null;
    final displayname = _resolveRoomDisplayName(context);
    final currentFilter = filter;
    if (currentFilter != null &&
        !displayname.toLowerCase().contains(currentFilter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender = lastEvent == null
        ? false
        : room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final currentSpace = space;

    final chatItem = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluffyThemes.spacing12,
        vertical: FluffyThemes.spacing4,
      ),
      child: HoverBuilder(
        builder: (context, isHovered) => AnimatedContainer(
          duration: FluffyThemes.durationFast,
          curve: FluffyThemes.curveStandard,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FluffyThemes.radiusLg),
            gradient: activeChat
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.25,
                      ),
                      theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.18,
                      ),
                      theme.colorScheme.tertiaryContainer.withValues(
                        alpha: 0.12,
                      ),
                    ],
                  )
                : isHovered
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
                    ],
                  )
                : null,
            border: activeChat
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  )
                : isHovered
                ? Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    width: 1,
                  )
                : null,
            boxShadow: activeChat
                ? FluffyThemes.layeredShadow(
                    context,
                    elevation: FluffyThemes.elevationMd,
                  )
                : isHovered
                ? FluffyThemes.shadow(
                    context,
                    elevation: FluffyThemes.elevationSm,
                  )
                : null,
          ),
          child: Material(
            borderRadius: BorderRadius.circular(FluffyThemes.radiusLg),
            clipBehavior: Clip.hardEdge,
            color: Colors.transparent,
            child: FutureBuilder(
              future: room.loadHeroUsers(),
              builder: (context, snapshot) => HoverBuilder(
                builder: (context, listTileHovered) => ListTile(
                  visualDensity: const VisualDensity(vertical: 0),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FluffyThemes.spacing12,
                    vertical: FluffyThemes.spacing4,
                  ),
                  // 移动端用长按，PC端用右键（Listener处理）
                  onLongPress: isDesktop
                      ? null
                      : () => onLongPress?.call(context),
                  leading: HoverBuilder(
                    builder: (context, hovered) => AnimatedScale(
                      duration: FluffyThemes.durationFast,
                      curve: FluffyThemes.curveBounce,
                      scale: hovered ? 1.08 : 1.0,
                      child: AnimatedContainer(
                        duration: FluffyThemes.durationFast,
                        curve: FluffyThemes.curveStandard,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            FluffyThemes.radiusFull,
                          ),
                          boxShadow: hovered
                              ? FluffyThemes.shadow(
                                  context,
                                  elevation: FluffyThemes.elevationSm,
                                )
                              : null,
                        ),
                        child: SizedBox(
                          width: Avatar.defaultSize,
                          height: Avatar.defaultSize,
                          child: Stack(
                            children: [
                              if (currentSpace != null)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Avatar(
                                    border: BorderSide(
                                      width: 2,
                                      color:
                                          backgroundColor ??
                                          theme.colorScheme.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      FluffyThemes.radiusMd,
                                    ),
                                    mxContent: currentSpace.avatar,
                                    size: Avatar.defaultSize * 0.75,
                                    name: currentSpace
                                        .getLocalizedDisplayname(),
                                    onTap: () => onLongPress?.call(context),
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Builder(
                                  builder: (context) {
                                    // 私聊时显示对方用户的头像
                                    final avatarSize = currentSpace != null
                                        ? Avatar.defaultSize * 0.75
                                        : Avatar.defaultSize;

                                    if (directChatMatrixId != null) {
                                      final agent = AgentService.instance
                                          .getAgentByMatrixUserId(
                                            directChatMatrixId,
                                          );
                                      if (agent != null) {
                                        final statusDotColor =
                                            _employeeWorkStatusColor(
                                          agent.computedWorkStatus,
                                        );
                                        // 优先使用员工头像（直接使用 avatarUrl 字符串，和 EmployeeCard 一样）
                                        if (agent.avatarUrl != null &&
                                            agent.avatarUrl!.isNotEmpty) {
                                          return _buildEmployeeAvatar(
                                            avatarUrl: agent.avatarUrl!,
                                            name: agent.displayName,
                                            size: avatarSize,
                                            border: currentSpace == null
                                                ? null
                                                : BorderSide(
                                                    width: 2,
                                                    color:
                                                        backgroundColor ??
                                                        theme.colorScheme.surface,
                                                  ),
                                            presenceBackgroundColor:
                                                backgroundColor,
                                            statusDotColor: statusDotColor,
                                            onTap: () =>
                                                onLongPress?.call(context),
                                          );
                                        }
                                        // 员工没有头像时，使用 Matrix 头像，但状态点仍使用员工工作状态。
                                        final user = room
                                            .unsafeGetUserFromMemoryOrFallback(
                                              directChatMatrixId,
                                            );
                                        return Avatar(
                                          border: currentSpace == null
                                              ? null
                                              : BorderSide(
                                                  width: 2,
                                                  color:
                                                      backgroundColor ??
                                                      theme.colorScheme.surface,
                                                ),
                                          borderRadius: null,
                                          mxContent: user.avatarUrl,
                                          size: avatarSize,
                                          name: agent.displayName,
                                          presenceBackgroundColor:
                                              backgroundColor,
                                          statusDotColor: statusDotColor,
                                          onTap: () =>
                                              onLongPress?.call(context),
                                        );
                                      }
                                      // 非员工使用 Matrix 用户头像 + Matrix 在线状态点
                                      final user = room
                                          .unsafeGetUserFromMemoryOrFallback(
                                            directChatMatrixId,
                                          );
                                      return Avatar(
                                        border: currentSpace == null
                                            ? null
                                            : BorderSide(
                                                width: 2,
                                                color:
                                                    backgroundColor ??
                                                    theme.colorScheme.surface,
                                              ),
                                        borderRadius: null,
                                        mxContent: user.avatarUrl,
                                        size: avatarSize,
                                        name:
                                            _resolveDisplayNameForMatrixUserId(
                                              matrixUserId: directChatMatrixId,
                                              matrixLocals: MatrixLocals(
                                                L10n.of(context),
                                              ),
                                            ),
                                        presenceUserId: directChatMatrixId,
                                        presenceBackgroundColor:
                                            backgroundColor,
                                        onTap: () => onLongPress?.call(context),
                                      );
                                    }
                                    // 群聊使用房间头像
                                    return Avatar(
                                      border: currentSpace == null
                                          ? null
                                          : BorderSide(
                                              width: 2,
                                              color:
                                                  backgroundColor ??
                                                  theme.colorScheme.surface,
                                            ),
                                      borderRadius: null,
                                      mxContent: room.avatar,
                                      size: avatarSize,
                                      name: displayname,
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
                                    duration: FluffyThemes.durationFast,
                                    curve: FluffyThemes.curveBounce,
                                    scale: listTileHovered ? 1.0 : 0.0,
                                    child: Material(
                                      color: backgroundColor,
                                      borderRadius: BorderRadius.circular(
                                        FluffyThemes.radiusLg,
                                      ),
                                      elevation: FluffyThemes.elevationSm,
                                      child: const Icon(
                                        Icons.arrow_drop_down_circle_outlined,
                                        size: FluffyThemes.iconSizeSm,
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
                          child: lastEvent == null
                              ? const SizedBox.shrink()
                              : Text(
                                  room.latestEventReceivedTime.localizedTimeShort(
                                    context,
                                  ),
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
                          lastEvent?.status.isSending == true) ...[
                        SizedBox(
                          width: FluffyThemes.iconSizeXs,
                          height: FluffyThemes.iconSizeXs,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: FluffyThemes.spacing4),
                      ],
                      AnimatedSize(
                        clipBehavior: Clip.hardEdge,
                        duration: FluffyThemes.durationFast,
                        curve: FluffyThemes.curveStandard,
                        child: typingText.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  right: FluffyThemes.spacing4,
                                ),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: FluffyThemes.durationNormal,
                                  curve: FluffyThemes.curveBounce,
                                  builder: (context, value, child) =>
                                      Transform.scale(
                                        scale: value,
                                        child: Icon(
                                          Icons.edit_outlined,
                                          color: theme.colorScheme.secondary,
                                          size: FluffyThemes.iconSizeXs,
                                        ),
                                      ),
                                ),
                              )
                            : lastEvent?.relationshipType ==
                                  RelationshipTypes.thread
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    FluffyThemes.radiusSm,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FluffyThemes.spacing8,
                                ),
                                margin: const EdgeInsets.only(
                                  right: FluffyThemes.spacing4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.message_outlined,
                                      size: FluffyThemes.fontSizeSm,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(
                                      width: FluffyThemes.spacing4,
                                    ),
                                    Text(
                                      L10n.of(context).thread,
                                      style: TextStyle(
                                        fontSize: FluffyThemes.fontSizeSm,
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
                                    ? lastEvent.calcLocalizedBodyWithAgents(
                                        MatrixLocals(L10n.of(context)),
                                        hideReply: true,
                                        hideEdit: true,
                                        plaintextBody: true,
                                        removeMarkdown: true,
                                        withSenderNamePrefix:
                                            (!isDirectChat ||
                                            directChatMatrixId !=
                                                lastEventSenderId),
                                      )
                                    : null,
                                initialData: lastEvent
                                    ?.calcLocalizedBodyFallbackWithAgents(
                                      MatrixLocals(L10n.of(context)),
                                      hideReply: true,
                                      hideEdit: true,
                                      plaintextBody: true,
                                      removeMarkdown: true,
                                      withSenderNamePrefix:
                                          (!isDirectChat ||
                                          directChatMatrixId !=
                                              lastEventSenderId),
                                    ),
                                builder: (context, snapshot) {
                                  final subtitleText =
                                      room.membership == Membership.invite
                                      ? room
                                                .getState(
                                                  EventTypes.RoomMember,
                                                  room.client.userID!,
                                                )
                                                ?.content
                                                .tryGet<String>('reason') ??
                                            (isDirectChat
                                                ? L10n.of(
                                                    context,
                                                  ).newChatRequest
                                                : L10n.of(
                                                    context,
                                                  ).inviteGroupChat)
                                      : snapshot.data ??
                                            L10n.of(context).noMessagesYet;
                                  return Text(
                                    _renderSubtitleText(
                                      context,
                                      subtitleText,
                                      lastEvent: lastEvent,
                                      isDirectChat: isDirectChat,
                                      directChatMatrixId: directChatMatrixId,
                                    ),
                                    softWrap: false,
                                    maxLines: room.notificationCount >= 1
                                        ? 2
                                        : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: unread || room.hasNewMessages
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.outline,
                                      decoration:
                                          lastEvent?.redacted == true
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  );
                                },
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
