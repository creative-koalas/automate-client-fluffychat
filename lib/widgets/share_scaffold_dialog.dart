import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/matrix.dart';

abstract class ShareItem {}

class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value);
}

class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  ContentShareItem(this.value);
}

class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value);
}

class ShareScaffoldDialog extends StatefulWidget {
  final List<ShareItem> items;

  const ShareScaffoldDialog({required this.items, super.key});

  @override
  State<ShareScaffoldDialog> createState() => _ShareScaffoldDialogState();
}

class _ShareScaffoldDialogState extends State<ShareScaffoldDialog> {
  final TextEditingController _filterController = TextEditingController();

  String? selectedRoomId;

  void _toggleRoom(String roomId) {
    setState(() {
      selectedRoomId = roomId;
    });
  }

  void _forwardAction() async {
    final roomId = selectedRoomId;
    if (roomId == null) {
      throw Exception(
        'Started forward action before room was selected. This should never happen.',
      );
    }
    while (context.canPop()) {
      context.pop();
    }
    context.go('/rooms/$roomId', extra: widget.items);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = Matrix.of(context)
        .client
        .rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: context.pop)),
        title: Text(L10n.of(context).share),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withAlpha(12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _filterController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(200),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withAlpha(30),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary.withAlpha(80),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  hintText: L10n.of(context).search,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                    fontWeight: FontWeight.normal,
                    fontSize: 15,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      Icons.search_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 46,
                    minHeight: 46,
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              final displayname = room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              );
              final value = selectedRoomId == room.id;
              final filterOut = !displayname.toLowerCase().contains(filter);
              if (!value && filterOut) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Opacity(
                  opacity: filterOut ? 0.5 : 1,
                  child: CheckboxListTile.adaptive(
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(90),
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConfig.borderRadius),
                    ),
                    secondary: Avatar(
                      mxContent: room.avatar,
                      name: displayname,
                      size: Avatar.defaultSize * 0.75,
                    ),
                    title: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      room.directChatMatrixID ??
                          L10n.of(context).countParticipants(
                            (room.summary.mJoinedMemberCount ?? 0) +
                                (room.summary.mInvitedMemberCount ?? 0),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: selectedRoomId == room.id,
                    onChanged: (_) => _toggleRoom(room.id),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: selectedRoomId == null
            ? const SizedBox.shrink()
            : Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withAlpha(15),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: FilledButton.icon(
                      onPressed: _forwardAction,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        L10n.of(context).forward,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
