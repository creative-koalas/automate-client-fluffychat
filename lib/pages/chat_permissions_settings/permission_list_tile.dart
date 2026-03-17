import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/l10n/l10n.dart';

class PermissionsListTile extends StatelessWidget {
  final String permissionKey;
  final int permission;
  final String? category;
  final void Function(int? level)? onChanged;
  final bool canEdit;

  const PermissionsListTile({
    super.key,
    required this.permissionKey,
    required this.permission,
    this.category,
    required this.onChanged,
    required this.canEdit,
  });

  String getLocalizedPowerLevelString(BuildContext context) {
    if (category == null) {
      switch (permissionKey) {
        case 'users_default':
          return L10n.of(context).defaultPermissionLevel;
        case 'events_default':
          return L10n.of(context).sendMessages;
        case 'state_default':
          return L10n.of(context).changeGeneralChatSettings;
        case 'ban':
          return L10n.of(context).banFromChat;
        case 'kick':
          return L10n.of(context).kickFromChat;
        case 'redact':
          return L10n.of(context).deleteMessage;
        case 'invite':
          return L10n.of(context).inviteOtherUsers;
      }
    } else if (category == 'notifications') {
      switch (permissionKey) {
        case 'rooms':
          return L10n.of(context).sendRoomNotifications;
      }
    } else if (category == 'events') {
      switch (permissionKey) {
        case EventTypes.RoomName:
          return L10n.of(context).changeTheNameOfTheGroup;
        case EventTypes.RoomTopic:
          return L10n.of(context).changeTheDescriptionOfTheGroup;
        case EventTypes.RoomPowerLevels:
          return L10n.of(context).changeTheChatPermissions;
        case EventTypes.HistoryVisibility:
          return L10n.of(context).changeTheVisibilityOfChatHistory;
        case EventTypes.RoomCanonicalAlias:
          return L10n.of(context).changeTheCanonicalRoomAlias;
        case EventTypes.RoomAvatar:
          return L10n.of(context).editRoomAvatar;
        case EventTypes.RoomTombstone:
          return L10n.of(context).replaceRoomWithNewerVersion;
        case EventTypes.Encryption:
          return L10n.of(context).enableEncryption;
        case 'm.room.server_acl':
          return L10n.of(context).editBlockedServers;
      }
    }
    return permissionKey;
  }

  /// 将权限值映射到最近的固定级别
  int _normalizeLevel(int level) {
    if (level >= 100) return 100;
    if (level >= 50) return 50;
    return 0;
  }

  String _getLevelLabel(BuildContext context, int level) {
    switch (level) {
      case 100:
        return L10n.of(context).owner;
      case 50:
        return L10n.of(context).moderator;
      default:
        return L10n.of(context).member;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedLevel = _normalizeLevel(permission);

    final color = normalizedLevel >= 100
        ? Colors.orangeAccent
        : normalizedLevel >= 50
            ? Colors.blueAccent
            : Colors.greenAccent;
    return ListTile(
      title: Text(
        getLocalizedPowerLevelString(context),
        style: theme.textTheme.titleSmall,
      ),
      trailing: Material(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        child: DropdownButton<int>(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          underline: const SizedBox.shrink(),
          onChanged: canEdit ? onChanged : null,
          value: normalizedLevel,
          items: [
            DropdownMenuItem(
              value: 0,
              child: Text(_getLevelLabel(context, 0)),
            ),
            DropdownMenuItem(
              value: 50,
              child: Text(_getLevelLabel(context, 50)),
            ),
            DropdownMenuItem(
              value: 100,
              child: Text(_getLevelLabel(context, 100)),
            ),
          ],
        ),
      ),
    );
  }
}
