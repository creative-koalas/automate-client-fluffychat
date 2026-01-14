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
    final theme = Theme.of(context);

    Widget buildMenuItem(IconData icon, String text, Color? iconColor) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? theme.colorScheme.primary).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: SettingsAction.newGroup,
        child: buildMenuItem(
          Icons.group_add_rounded,
          L10n.of(context).createGroup,
          theme.colorScheme.tertiary,
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.setStatus,
        child: buildMenuItem(
          Icons.edit_rounded,
          L10n.of(context).setStatus,
          theme.colorScheme.secondary,
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.invite,
        child: buildMenuItem(
          Icons.adaptive.share_rounded,
          L10n.of(context).inviteContact,
          theme.colorScheme.primary,
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.settings,
        child: buildMenuItem(
          Icons.settings_rounded,
          L10n.of(context).settings,
          theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final theme = Theme.of(context);

    // 使用 userID 作为 key，当用户变化时强制重建 FutureBuilder
    return FutureBuilder<Profile>(
      key: ValueKey(client.userID),
      future: client.isLogged() ? client.fetchOwnProfile() : null,
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
              name: snapshot.data?.displayName ?? client.userID?.localpart,
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
