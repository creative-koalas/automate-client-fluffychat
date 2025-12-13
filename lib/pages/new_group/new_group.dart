import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/new_group/new_group_view.dart';
import 'package:psygo/utils/file_selector.dart';
import 'package:psygo/widgets/matrix.dart';

class NewGroup extends StatefulWidget {
  final CreateGroupType createGroupType;
  const NewGroup({
    this.createGroupType = CreateGroupType.group,
    super.key,
  });

  @override
  NewGroupController createState() => NewGroupController();
}

class NewGroupController extends State<NewGroup> {
  TextEditingController nameController = TextEditingController();

  bool publicGroup = false;
  bool groupCanBeFound = false;

  Uint8List? avatar;

  Uri? avatarUrl;

  Object? error;

  bool loading = false;

  CreateGroupType get createGroupType =>
      _createGroupType ?? widget.createGroupType;

  CreateGroupType? _createGroupType;

  void setCreateGroupType(Set<CreateGroupType> b) =>
      setState(() => _createGroupType = b.single);

  void setPublicGroup(bool b) =>
      setState(() => publicGroup = groupCanBeFound = b);

  void setGroupCanBeFound(bool b) => setState(() => groupCanBeFound = b);

  void selectPhoto() async {
    final photo = await selectFiles(
      context,
      type: FileSelectorType.images,
      allowMultiple: false,
    );
    final bytes = await photo.singleOrNull?.readAsBytes();

    setState(() {
      avatarUrl = null;
      avatar = bytes;
    });
  }

  Future<void> _createGroup() async {
    if (!mounted) return;
    final roomId = await Matrix.of(context).client.createGroupChat(
      enableEncryption: false,
      visibility:
          groupCanBeFound ? sdk.Visibility.public : sdk.Visibility.private,
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      groupName: nameController.text.isNotEmpty ? nameController.text : null,
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ],
    );
    if (!mounted) return;
    context.go('/rooms/$roomId/invite');
  }

  void submitAction([_]) async {
    final client = Matrix.of(context).client;

    try {
      setState(() {
        loading = true;
        error = null;
      });

      final avatar = this.avatar;
      avatarUrl ??= avatar == null ? null : await client.uploadContent(avatar);

      if (!mounted) return;

      await _createGroup();
    } catch (e, s) {
      sdk.Logs().d('Unable to create group', e, s);
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => NewGroupView(this);
}

enum CreateGroupType { group }
