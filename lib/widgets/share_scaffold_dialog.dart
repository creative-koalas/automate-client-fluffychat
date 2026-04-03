import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat/send_file_dialog.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/other_party_can_receive.dart';
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

  final Set<String> _selectedRoomIds = <String>{};
  bool _isForwarding = false;

  void _closeDialog() {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _toggleRoom(String roomId) {
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
      } else {
        _selectedRoomIds.add(roomId);
      }
    });
  }

  Map<String, dynamic> _sanitizeForwardContent(Map<String, Object?> content) {
    final forwarded = Map<String, dynamic>.from(content);
    // Forwarded messages should be independent from source room relations.
    forwarded.remove('m.relates_to');
    forwarded.remove('m.new_content');
    return forwarded;
  }

  void _showErrorSnackBar(Object error) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: theme.colorScheme.errorContainer,
        closeIconColor: theme.colorScheme.onErrorContainer,
        content: Text(
          error.toLocalizedString(context),
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        duration: const Duration(seconds: 30),
        showCloseIcon: true,
      ),
    );
  }

  void _forwardAction() async {
    if (_isForwarding) return;
    if (_selectedRoomIds.isEmpty) {
      throw Exception(
        'Started forward action before any room was selected. This should never happen.',
      );
    }
    final rooms = _selectedRoomIds
        .map(Matrix.of(context).client.getRoomById)
        .whereType<Room>()
        .toList();
    if (rooms.length != _selectedRoomIds.length) {
      _showErrorSnackBar(L10n.of(context).oopsSomethingWentWrong);
      return;
    }

    final hasFiles = widget.items.any((item) => item is FileShareItem);
    if (hasFiles) {
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final files = widget.items
          .whereType<FileShareItem>()
          .map((item) => item.value)
          .toList();
      _closeDialog();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAdaptiveDialog<void>(
          context: rootContext,
          builder: (dialogContext) => SendFileDialog(
            rooms: rooms,
            files: files,
            outerContext: rootContext,
            replyEvent: null,
            threadRootEventId: null,
            threadLastEventId: null,
          ),
        );
      });
      return;
    }

    setState(() => _isForwarding = true);
    try {
      for (final room in rooms) {
        if (!room.otherPartyCanReceiveMessages) {
          throw OtherPartyCanNotReceiveMessages();
        }
        for (final item in widget.items) {
          String? sentEventId;
          if (item is TextShareItem) {
            sentEventId = await room.sendTextEvent(
              item.value,
              parseCommands: false,
            );
          } else if (item is ContentShareItem) {
            sentEventId =
                await room.sendEvent(_sanitizeForwardContent(item.value));
          }
          if (sentEventId == null) {
            throw L10n.of(context).serverError;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e);
      return;
    } finally {
      if (mounted) {
        setState(() => _isForwarding = false);
      }
    }

    _closeDialog();
    if (rooms.length == 1) {
      final router = GoRouter.of(context);
      router.go('/rooms/${rooms.single.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = Matrix.of(context)
        .client
        .rooms
        .where(
          (room) =>
              room.canSendDefaultMessages && room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: _closeDialog)),
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
                  fillColor:
                      theme.colorScheme.surfaceContainerHighest.withAlpha(200),
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
              final value = _selectedRoomIds.contains(room.id);
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
                    value: value,
                    onChanged: (_) => _toggleRoom(room.id),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: FluffyThemes.durationFast,
        curve: FluffyThemes.curveStandard,
        child: _selectedRoomIds.isEmpty
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
                      onPressed: _isForwarding ? null : _forwardAction,
                      icon: _isForwarding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
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
