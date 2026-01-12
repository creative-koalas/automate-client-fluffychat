import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_details/chat_details.dart';
import 'package:psygo/pages/chat_details/participant_list_item.dart';
import 'package:psygo/utils/fluffy_share.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/chat_settings_popup_menu.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../utils/url_launcher.dart';
import '../../widgets/mxc_image_viewer.dart';
import '../../widgets/qr_code_viewer.dart';

class ChatDetailsView extends StatelessWidget {
  final ChatDetailsController controller;

  const ChatDetailsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final room = Matrix.of(context).client.getRoomById(controller.roomId!);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).oopsSomethingWentWrong),
        ),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    final directChatMatrixID = room.directChatMatrixID;

    return StreamBuilder(
      stream: room.client.onRoomState.stream
          .where((update) => update.roomId == room.id),
      builder: (context, snapshot) {
        var members = room.getParticipants().toList()
          ..sort((b, a) => a.powerLevel.compareTo(b.powerLevel));
        members = members.take(10).toList();
        final actualMembersCount = (room.summary.mInvitedMemberCount ?? 0) +
            (room.summary.mJoinedMemberCount ?? 0);
        final canRequestMoreMembers = members.length < actualMembersCount;
        final iconColor = theme.textTheme.bodyLarge!.color;
        final displayname = room.getLocalizedDisplayname(
          MatrixLocals(L10n.of(context)),
        );
        return Scaffold(
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.95),
          appBar: AppBar(
            leading: controller.widget.embeddedCloseButton ??
                const Center(child: BackButton()),
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
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
            ),
            actions: <Widget>[
              if (room.canonicalAlias.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: L10n.of(context).share,
                    icon: Icon(
                      Icons.qr_code_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () => showQrCodeViewer(
                      context,
                      room.canonicalAlias,
                    ),
                  ),
                )
              else if (directChatMatrixID != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: L10n.of(context).share,
                    icon: Icon(
                      Icons.qr_code_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () => showQrCodeViewer(
                      context,
                      directChatMatrixID,
                    ),
                  ),
                ),
              if (controller.widget.embeddedCloseButton == null)
                ChatSettingsPopupMenu(room, false),
            ],
            title: Text(
              L10n.of(context).chatDetails,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: -0.3,
              ),
            ),
          ),
          body: MaxWidthBody(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: members.length + 1 + (canRequestMoreMembers ? 1 : 0),
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primaryContainer.withValues(alpha: 0.08),
                                theme.colorScheme.surfaceContainerLow,
                                theme.colorScheme.secondaryContainer.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                                blurRadius: 16,
                                spreadRadius: -4,
                                offset: const Offset(0, 6),
                              ),
                              BoxShadow(
                                color: theme.colorScheme.shadow.withAlpha(8),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      theme.colorScheme.primary.withValues(alpha: 0.15),
                                      theme.colorScheme.tertiary.withValues(alpha: 0.1),
                                    ],
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.surface,
                                  ),
                                  child: Hero(
                                    tag:
                                        controller.widget.embeddedCloseButton !=
                                                null
                                            ? 'embedded_content_banner'
                                            : 'content_banner',
                                    child: Builder(
                                      builder: (context) {
                                        // 私聊时显示对方用户的头像
                                        Uri? avatarUrl = room.avatar;
                                        String avatarName = displayname;
                                        if (directChatMatrixID != null) {
                                          final user = room.unsafeGetUserFromMemoryOrFallback(directChatMatrixID);
                                          avatarUrl = user.avatarUrl;
                                          avatarName = user.calcDisplayname();
                                        }
                                        return Avatar(
                                          mxContent: avatarUrl,
                                          name: avatarName,
                                          size: Avatar.defaultSize * 2.5,
                                          onTap: avatarUrl != null
                                              ? () => showDialog(
                                                    context: context,
                                                    builder: (_) =>
                                                        MxcImageViewer(avatarUrl!),
                                                  )
                                              : null,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => room.isDirectChat
                                        ? null
                                        : room.canChangeStateEvent(
                                            EventTypes.RoomName,
                                          )
                                            ? controller.setDisplaynameAction()
                                            : FluffyShare.share(
                                                displayname,
                                                context,
                                                copyOnly: true,
                                              ),
                                    icon: Icon(
                                      room.isDirectChat
                                          ? Icons.chat_bubble_outline
                                          : room.canChangeStateEvent(
                                              EventTypes.RoomName,
                                            )
                                              ? Icons.edit_outlined
                                              : Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.onSurface,
                                      iconColor: theme.colorScheme.onSurface,
                                    ),
                                    label: Text(
                                      room.isDirectChat
                                          ? L10n.of(context).directChat
                                          : displayname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => room.isDirectChat
                                        ? null
                                        : context.push(
                                            '/rooms/${controller.roomId}/details/members',
                                          ),
                                    icon: const Icon(
                                      Icons.group_outlined,
                                      size: 14,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.secondary,
                                      iconColor: theme.colorScheme.secondary,
                                    ),
                                    label: Text(
                                      L10n.of(context).countParticipants(
                                        actualMembersCount,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      //    style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                        if (room.canChangeStateEvent(EventTypes.RoomTopic) ||
                            room.topic.isNotEmpty) ...[
                          Divider(color: theme.dividerColor),
                          ListTile(
                            title: Text(
                              L10n.of(context).chatDescription,
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing:
                                room.canChangeStateEvent(EventTypes.RoomTopic)
                                    ? IconButton(
                                        onPressed: controller.setTopicAction,
                                        tooltip:
                                            L10n.of(context).setChatDescription,
                                        icon: const Icon(Icons.edit_outlined),
                                      )
                                    : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: SelectableLinkify(
                              text: room.topic.isEmpty
                                  ? L10n.of(context).noChatDescriptionYet
                                  : room.topic,
                              textScaleFactor:
                                  MediaQuery.textScalerOf(context).scale(1),
                              options: const LinkifyOptions(humanize: false),
                              linkStyle: const TextStyle(
                                color: Colors.blueAccent,
                                decorationColor: Colors.blueAccent,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: room.topic.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: theme.textTheme.bodyMedium!.color,
                                decorationColor:
                                    theme.textTheme.bodyMedium!.color,
                              ),
                              onOpen: (url) =>
                                  UrlLauncher(context, url.url).launchUrl(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!room.isDirectChat) ...[
                          Divider(color: theme.dividerColor),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                            ),
                            title: Text(
                              L10n.of(context).accessAndVisibility,
                            ),
                            subtitle: Text(
                              L10n.of(context).accessAndVisibilityDescription,
                            ),
                            onTap: () => context
                                .push('/rooms/${room.id}/details/access'),
                            trailing: const Icon(Icons.chevron_right_outlined),
                          ),
                          ListTile(
                            title: Text(L10n.of(context).chatPermissions),
                            subtitle: Text(
                              L10n.of(context).whoCanPerformWhichAction,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(
                                Icons.tune_outlined,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                            onTap: () => context
                                .push('/rooms/${room.id}/details/permissions'),
                          ),
                        ],
                        Divider(color: theme.dividerColor),
                        ListTile(
                          title: Text(
                            L10n.of(context).countParticipants(
                              actualMembersCount,
                            ),
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!room.isDirectChat && room.canInvite)
                          ListTile(
                            title: Text(L10n.of(context).inviteContact),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              radius: Avatar.defaultSize / 2,
                              child: const Icon(Icons.add_outlined),
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                            onTap: () => context.go('/rooms/${room.id}/invite'),
                          ),
                      ],
                    )
                  : i < members.length + 1
                      ? ParticipantListItem(members[i - 1])
                      : ListTile(
                          title: Text(
                            L10n.of(context).loadCountMoreParticipants(
                              (actualMembersCount - members.length),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: theme.scaffoldBackgroundColor,
                            child: const Icon(
                              Icons.group_outlined,
                              color: Colors.grey,
                            ),
                          ),
                          onTap: () => context.push(
                            '/rooms/${controller.roomId!}/details/members',
                          ),
                          trailing: const Icon(Icons.chevron_right_outlined),
                        ),
            ),
          ),
        );
      },
    );
  }
}
