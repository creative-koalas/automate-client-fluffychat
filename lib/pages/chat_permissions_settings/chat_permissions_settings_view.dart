import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:psygo/pages/chat_permissions_settings/permission_list_tile.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';
import 'package:psygo/widgets/matrix.dart';

class ChatPermissionsSettingsView extends StatelessWidget {
  final ChatPermissionsSettingsController controller;

  const ChatPermissionsSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).chatPermissions),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          stream: controller.onChanged,
          builder: (context, _) {
            final roomId = controller.roomId;
            final room = roomId == null
                ? null
                : Matrix.of(context).client.getRoomById(roomId);
            if (room == null) {
              return Center(child: Text(L10n.of(context).noRoomsFound));
            }
            final powerLevelsContent = Map<String, Object?>.from(
              room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
            );
            final powerLevels = Map<String, dynamic>.from(powerLevelsContent)
              ..removeWhere((k, v) => v is! int);
            final eventsPowerLevels = Map<String, int?>.from(
              powerLevelsContent.tryGetMap<String, int?>('events') ?? {},
            )..removeWhere((k, v) => v is! int);

            // 只显示核心权限项
            const coreKeys = ['invite', 'kick', 'ban', 'redact'];
            const coreEventKeys = [
              EventTypes.RoomName,
              EventTypes.RoomTopic,
              EventTypes.RoomPowerLevels,
            ];

            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outlined),
                  subtitle: Text(
                    L10n.of(context).chatPermissionsDescription,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ListTile(
                  title: Text(
                    L10n.of(context).chatPermissions,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final key in coreKeys)
                      if (powerLevels.containsKey(key))
                        PermissionsListTile(
                          permissionKey: key,
                          permission: powerLevels[key] as int,
                          onChanged: (level) => controller.editPowerLevel(
                            context,
                            key,
                            powerLevels[key] as int,
                            newLevel: level,
                          ),
                          canEdit: room.canChangePowerLevel,
                        ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: Text(
                        L10n.of(context).configureChat,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (final key in coreEventKeys)
                      if (eventsPowerLevels.containsKey(key))
                        PermissionsListTile(
                          permissionKey: key,
                          category: 'events',
                          permission: eventsPowerLevels[key] ?? 0,
                          canEdit: room.canChangePowerLevel,
                          onChanged: (level) => controller.editPowerLevel(
                            context,
                            key,
                            eventsPowerLevels[key] ?? 0,
                            newLevel: level,
                            category: 'events',
                          ),
                        ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
