import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/invitation_selection/invitation_selection_view.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../utils/localized_exception_extension.dart';

class InvitationSelection extends StatefulWidget {
  final String roomId;
  const InvitationSelection({
    super.key,
    required this.roomId,
  });

  @override
  InvitationSelectionController createState() =>
      InvitationSelectionController();
}

class InvitationSelectionController extends State<InvitationSelection> {
  TextEditingController controller = TextEditingController();
  late String currentSearchTerm;
  bool loading = false;
  List<Profile> foundProfiles = [];
  Set<String> memberIds = <String>{};
  Timer? coolDown;
  StreamSubscription? _roomStateSub;

  String? get roomId => widget.roomId;

  Future<void> _refreshMemberIds() async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    if (room == null) return;

    try {
      final participants = await room.requestParticipants(
        [...Membership.values]..remove(Membership.leave),
      );
      if (!mounted) return;
      setState(() {
        memberIds = participants.map((u) => u.id).toSet();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        memberIds = room.getParticipants().map((u) => u.id).toSet();
      });
    }
  }

  bool _isAlreadyInRoomError(Object error) {
    if (error is! MatrixException) return false;
    final message = error.errorMessage.toLowerCase();
    return message.contains('already in the room') ||
        message.contains('already joined') ||
        message.contains('already a member') ||
        message.contains('is in room') ||
        message.contains('already invited') ||
        message.contains('已在') ||
        message.contains('已经在');
  }

  Future<List<User>> getContacts(BuildContext context) async {
    final client = Matrix.of(context).client;
    final contacts = client.rooms
        .where((r) => r.isDirectChat)
        .map((r) => r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!))
        .toList();
    contacts.sort(
      (a, b) => a.calcDisplayname().toLowerCase().compareTo(
            b.calcDisplayname().toLowerCase(),
          ),
    );
    return contacts;
  }

  void inviteAction(BuildContext context, String id, String displayname) async {
    final l10n = L10n.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    if (!room.canInvite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noPermission)),
      );
      return;
    }
    if (memberIds.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userAlreadyInGroup)),
      );
      return;
    }

    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        try {
          await room.invite(id);
        } on MatrixException catch (e) {
          if (_isAlreadyInRoomError(e)) {
            throw l10n.userAlreadyInGroup;
          }
          rethrow;
        }
      },
    );
    if (success.error == null) {
      setState(() {
        memberIds = {...memberIds, id};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).contactHasBeenInvitedToTheGroup),
        ),
      );
    }
  }

  void searchUserWithCoolDown(String text) async {
    coolDown?.cancel();
    coolDown = Timer(
      const Duration(milliseconds: 500),
      () => searchUser(context, text),
    );
  }

  void searchUser(BuildContext context, String text) async {
    coolDown?.cancel();
    if (text.isEmpty) {
      setState(() => foundProfiles = []);
    }
    currentSearchTerm = text;
    if (currentSearchTerm.isEmpty) return;
    if (loading) return;
    setState(() => loading = true);
    final matrix = Matrix.of(context);
    SearchUserDirectoryResponse response;
    try {
      response = await matrix.client.searchUserDirectory(text, limit: 10);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((e).toLocalizedString(context))),
      );
      return;
    } finally {
      setState(() => loading = false);
    }
    setState(() {
      foundProfiles = List<Profile>.from(response.results);
      if (text.isValidMatrixId &&
          foundProfiles.indexWhere((profile) => text == profile.userId) == -1) {
        setState(
          () => foundProfiles = [
            Profile.fromJson({'user_id': text}),
          ],
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshMemberIds();
    _roomStateSub = Matrix.of(context)
        .client
        .onSync
        .stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[roomId]?.timeline?.events
                  ?.any((event) => event.type == EventTypes.RoomMember) ??
              false,
        )
        .listen((_) => _refreshMemberIds());
  }

  @override
  void dispose() {
    coolDown?.cancel();
    controller.dispose();
    _roomStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InvitationSelectionView(this);
}
