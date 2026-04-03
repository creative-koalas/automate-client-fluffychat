import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/models/invite_candidate.dart';
import 'package:psygo/pages/invitation_selection/invitation_selection.dart';
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
                final isSearchMode =
                    controller.controller.text.trim().isNotEmpty ||
                        controller.loading;
                return isSearchMode
                    ? controller.foundCandidates.isEmpty && !controller.loading
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                L10n.of(context).noUsersFoundWithQuery(
                                  controller.controller.text.trim(),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: controller.foundCandidates.length,
                            itemBuilder: (BuildContext context, int i) =>
                                _InviteContactListTile(
                              candidate: controller.foundCandidates[i],
                              canInvite: room.canInvite,
                              isMember: participants.contains(
                                controller.foundCandidates[i].matrixUserId,
                              ),
                              onTap: () => controller.inviteAction(
                                context,
                                controller.foundCandidates[i].matrixUserId,
                                controller.foundCandidates[i].displayName,
                              ),
                            ),
                          )
                    : FutureBuilder<List<InviteCandidate>>(
                        future: controller.getContacts(context),
                        builder: (BuildContext context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          final contacts = snapshot.data!;
                          return ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: contacts.length,
                            itemBuilder: (BuildContext context, int i) =>
                                _InviteContactListTile(
                              candidate: contacts[i],
                              canInvite: room.canInvite,
                              isMember: participants
                                  .contains(contacts[i].matrixUserId),
                              onTap: () => controller.inviteAction(
                                context,
                                contacts[i].matrixUserId,
                                contacts[i].displayName,
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
  final InviteCandidate candidate;
  final bool canInvite;
  final bool isMember;
  final void Function() onTap;

  const _InviteContactListTile({
    required this.candidate,
    required this.canInvite,
    required this.isMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return ListTile(
      leading: Avatar(
        mxContent: candidate.avatarUrl,
        name: candidate.displayName,
        presenceUserId: candidate.matrixUserId,
        onTap: () => UserDialog.show(
          context: context,
          profile: candidate.toProfile(),
        ),
      ),
      title: Text(
        candidate.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        candidate.secondaryIdentifier,
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
}
