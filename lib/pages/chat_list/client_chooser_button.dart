import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../utils/fluffy_share.dart';
import 'chat_list.dart';

class ClientChooserButton extends StatelessWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  List<PopupMenuEntry<Object>> _bundleMenuItems(BuildContext context) {
    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: SettingsAction.newGroup,
        child: Row(
          children: [
            const Icon(Icons.group_add_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).createGroup),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.setStatus,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).setStatus),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.invite,
        child: Row(
          children: [
            Icon(Icons.adaptive.share_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).inviteContact),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).settings),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);

    return FutureBuilder<Profile>(
      future: matrix.client.isLogged() ? matrix.client.fetchOwnProfile() : null,
      builder: (context, snapshot) => Material(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(99),
        color: Colors.transparent,
        child: PopupMenuButton<Object>(
          popUpAnimationStyle: FluffyThemes.isColumnMode(context)
              ? AnimationStyle.noAnimation
              : null, // https://github.com/flutter/flutter/issues/167180
          onSelected: (o) => _clientSelected(o, context),
          itemBuilder: _bundleMenuItems,
          child: Center(
            child: Avatar(
              mxContent: snapshot.data?.avatarUrl,
              name:
                  snapshot.data?.displayName ?? matrix.client.userID?.localpart,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  void _clientSelected(
    Object object,
    BuildContext context,
  ) async {
    if (object is SettingsAction) {
      switch (object) {
        case SettingsAction.newGroup:
          context.go('/rooms/newgroup');
          break;
        case SettingsAction.invite:
          FluffyShare.shareInviteLink(context);
          break;
        case SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case SettingsAction.setStatus:
          controller.setStatus();
          break;
      }
    }
  }
}

enum SettingsAction {
  newGroup,
  setStatus,
  invite,
  settings,
}
