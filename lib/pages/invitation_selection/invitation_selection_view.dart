import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/invitation_selection/invitation_selection.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_sdk_extensions/agent_presentation_extension.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';

class InvitationSelectionView extends StatelessWidget {
  final InvitationSelectionController controller;

  const InvitationSelectionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room =
        Matrix.of(context).client.getRoomById(controller.widget.roomId);
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

    final groupName = room.name.isEmpty ? L10n.of(context).group : room.name;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        titleSpacing: 0,
        title: Text(L10n.of(context).inviteContact),
      ),
      body: MaxWidthBody(
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                  hintText: L10n.of(context).inviteContactToGroup(groupName),
                  prefixIcon: controller.loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 10.0,
                            horizontal: 12,
                          ),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : const Icon(Icons.search_outlined),
                ),
                onChanged: controller.searchUserWithCoolDown,
              ),
            ),
            StreamBuilder<Object>(
              stream: room.client.onRoomState.stream
                  .where((update) => update.roomId == room.id),
              builder: (context, snapshot) {
                final participants = {
                  ...room.getParticipants().map((user) => user.id),
                  ...controller.memberIds,
                };
                return controller.foundProfiles.isNotEmpty
                    ? ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: controller.foundProfiles.length,
                        itemBuilder: (BuildContext context, int i) =>
                            _InviteContactListTile(
                          profile: controller.foundProfiles[i],
                          canInvite: room.canInvite,
                          isMember: participants
                              .contains(controller.foundProfiles[i].userId),
                          onTap: () => controller.inviteAction(
                            context,
                            controller.foundProfiles[i].userId,
                            controller.foundProfiles[i].displayName ??
                                controller.foundProfiles[i].userId.localpart ??
                                L10n.of(context).user,
                          ),
                        ),
                      )
                    : FutureBuilder<List<User>>(
                        future: controller.getContacts(context),
                        builder: (BuildContext context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          final matrixLocals = MatrixLocals(L10n.of(context));
                          final contacts = snapshot.data!;
                          return ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: contacts.length,
                            itemBuilder: (BuildContext context, int i) =>
                                _InviteContactListTile(
                              user: contacts[i],
                              canInvite: room.canInvite,
                              profile: Profile(
                                avatarUrl: contacts[i].avatarUrl,
                                displayName:
                                    contacts[i].calcDisplaynameWithAgents(
                                  i18n: matrixLocals,
                                ),
                                userId: contacts[i].id,
                              ),
                              isMember: participants.contains(contacts[i].id),
                              onTap: () => controller.inviteAction(
                                context,
                                contacts[i].id,
                                contacts[i].calcDisplaynameWithAgents(
                                  i18n: matrixLocals,
                                ),
                              ),
                            ),
                          );
                        },
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteContactListTile extends StatelessWidget {
  final Profile profile;
  final User? user;
  final bool canInvite;
  final bool isMember;
  final void Function() onTap;

  const _InviteContactListTile({
    required this.profile,
    this.user,
    required this.canInvite,
    required this.isMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final directChatRoomId = client.getDirectChatFromUserId(profile.userId);
    final directChatRoom =
        directChatRoomId == null ? null : client.getRoomById(directChatRoomId);
    final matrixLocals = MatrixLocals(l10n);
    final roomDisplayName =
        directChatRoom?.getLocalizedDisplaynameWithAgents(matrixLocals).trim();
    final agentDisplayName = AgentService.instance
        .getAgentByMatrixUserId(profile.userId)
        ?.displayName;
    final displayName = _resolveDisplayName(
      l10n,
      roomDisplayName,
      agentDisplayName,
    );

    return ListTile(
      leading: Avatar(
        mxContent: AgentService.instance.getAgentAvatarUri(profile.userId) ??
            user?.avatarUrl ??
            profile.avatarUrl,
        name: displayName,
        presenceUserId: profile.userId,
        onTap: () => UserDialog.show(
          context: context,
          profile: profile,
        ),
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        profile.userId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.colorScheme.secondary,
        ),
      ),
      trailing: TextButton.icon(
        onPressed: isMember || !canInvite ? null : onTap,
        label: Text(
          isMember
              ? l10n.participant
              : (canInvite ? l10n.invite : l10n.noPermission),
        ),
        icon: Icon(
          isMember
              ? Icons.check
              : (canInvite ? Icons.add : Icons.block_outlined),
        ),
      ),
    );
  }

  String _resolveDisplayName(
    L10n l10n,
    String? roomDisplayName,
    String? agentDisplayName,
  ) {
    final normalizedRoomDisplayName = roomDisplayName?.trim();
    if (normalizedRoomDisplayName != null &&
        normalizedRoomDisplayName.isNotEmpty &&
        normalizedRoomDisplayName != profile.userId) {
      return normalizedRoomDisplayName;
    }

    final normalizedAgentDisplayName = agentDisplayName?.trim();
    if (normalizedAgentDisplayName != null &&
        normalizedAgentDisplayName.isNotEmpty) {
      return normalizedAgentDisplayName;
    }

    final userDisplayName = user?.calcDisplaynameWithAgents(
      i18n: MatrixLocals(l10n),
    );
    final normalizedUserDisplayName = userDisplayName?.trim();
    if (normalizedUserDisplayName != null &&
        normalizedUserDisplayName.isNotEmpty &&
        normalizedUserDisplayName != profile.userId) {
      return normalizedUserDisplayName;
    }

    final profileDisplayName = profile.displayName?.trim();
    if (profileDisplayName != null &&
        profileDisplayName.isNotEmpty &&
        profileDisplayName != profile.userId) {
      return profileDisplayName;
    }

    return profile.userId.localpart ?? l10n.user;
  }
}
