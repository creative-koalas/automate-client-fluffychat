import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_permissions_settings/chat_permissions_settings_view.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/matrix.dart';

class ChatPermissionsSettings extends StatefulWidget {
  const ChatPermissionsSettings({super.key});

  @override
  ChatPermissionsSettingsController createState() =>
      ChatPermissionsSettingsController();
}

class ChatPermissionsSettingsController
    extends State<ChatPermissionsSettings> {
  String? get roomId => GoRouterState.of(context).pathParameters['roomid'];

  Room? get room {
    final id = roomId;
    if (id == null || id.isEmpty) return null;
    return Matrix.of(context).client.getRoomById(id);
  }

  bool get isOwner => room != null && room!.ownPowerLevel >= 100;

  /// 同步获取成员列表（和聊天详情页一样的方式）
  List<User> getMembers() {
    final r = room;
    if (r == null) return [];
    return r.getParticipants().toList()
      ..sort((b, a) => a.powerLevel.compareTo(b.powerLevel));
  }

  /// 修改成员权限等级
  void setMemberPowerLevel(User user, int newLevel) async {
    final r = room;
    if (r == null) return;

    if (r.ownPowerLevel < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).noPermission)),
      );
      return;
    }

    if (user.id == r.client.userID) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).noPermission)),
      );
      return;
    }

    await showFutureLoadingDialog(
      context: context,
      future: () => user.setPower(newLevel),
    );
  }

  /// 显示权限选择弹窗
  void showRoleDialog(User user) async {
    final currentLevel = user.powerLevel >= 50 ? 50 : 0;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(L10n.of(context).chatPermissions),
        children: [
          for (final entry in [
            (0, L10n.of(context).member),
            (50, L10n.of(context).moderator),
          ])
            ListTile(
              leading: Icon(
                entry.$1 == currentLevel
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: entry.$1 == currentLevel
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(entry.$2),
              onTap: () => Navigator.of(context).pop(entry.$1),
            ),
        ],
      ),
    );
    if (selected == null || selected == currentLevel) return;
    if (!mounted) return;
    setMemberPowerLevel(user, selected);
  }

  @override
  Widget build(BuildContext context) => ChatPermissionsSettingsView(this);
}
