import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/room_display_name.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';

import 'package:matrix/matrix.dart';

class ChatPermissionsSettingsView extends StatelessWidget {
  final ChatPermissionsSettingsController controller;

  const ChatPermissionsSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = controller.room;

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(l10n.chatPermissions),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        child: room == null
            ? Center(child: Text(l10n.noRoomsFound))
            : StreamBuilder(
                stream: room.client.onRoomState.stream
                    .where((update) => update.roomId == room.id),
                builder: (context, _) {
                  final members = controller.getMembers();

                  // 按权限等级分组
                  final owners =
                      members.where((u) => u.powerLevel >= 100).toList();
                  final admins = members
                      .where(
                        (u) => u.powerLevel >= 50 && u.powerLevel < 100,
                      )
                      .toList();
                  final normalMembers =
                      members.where((u) => u.powerLevel < 50).toList();

                  return ListView(
                    children: [
                      if (owners.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.owner,
                          count: owners.length,
                          color: Colors.orangeAccent,
                        ),
                        for (final user in owners)
                          _MemberTile(
                            user: user,
                            canEdit: false,
                            onEditRole: null,
                          ),
                      ],
                      if (admins.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.moderator,
                          count: admins.length,
                          color: Colors.blueAccent,
                        ),
                        for (final user in admins)
                          _MemberTile(
                            user: user,
                            canEdit: controller.isOwner,
                            onEditRole: controller.isOwner
                                ? () => controller.showRoleDialog(user)
                                : null,
                          ),
                      ],
                      if (normalMembers.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.member,
                          count: normalMembers.length,
                          color: Colors.greenAccent,
                        ),
                        for (final user in normalMembers)
                          _MemberTile(
                            user: user,
                            canEdit: controller.isOwner,
                            onEditRole: controller.isOwner
                                ? () => controller.showRoleDialog(user)
                                : null,
                          ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final User user;
  final bool canEdit;
  final VoidCallback? onEditRole;

  const _MemberTile({
    required this.user,
    required this.canEdit,
    this.onEditRole,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agentService = AgentService.instance;
    final matrixLocals = MatrixLocals(L10n.of(context));
    final isMe = user.room.client.userID == user.id;

    return ValueListenableBuilder<int>(
      valueListenable: agentService.profileNotifier,
      builder: (context, _, __) {
        final displayname = resolveDisplayNameForMatrixUserId(
          room: user.room,
          matrixUserId: user.id,
          matrixLocals: matrixLocals,
        );
        final avatarUrl = agentService.resolveAvatarUriByMatrixUserId(
          user.id,
          fallbackAvatarUri: user.avatarUrl,
        );

        return ListTile(
          leading: Avatar(
            mxContent: avatarUrl,
            name: displayname,
            presenceUserId: user.stateKey,
          ),
          title: Text(
            displayname,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            user.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: canEdit && !isMe
              ? IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: L10n.of(context).chatPermissions,
                  onPressed: onEditRole,
                )
              : null,
        );
      },
    );
  }
}
