import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:animations/animations.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat/recording_input_row.dart';
import 'package:psygo/pages/chat/recording_view_model.dart';
import 'package:psygo/utils/other_party_can_receive.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../config/themes.dart';
import 'chat.dart';
import 'input_bar.dart';

class ChatInputRow extends StatelessWidget {
  final ChatController controller;

  const ChatInputRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPendingAttachments =
        PlatformInfos.isDesktop && controller.hasPendingAttachments;

    const height = 48.0;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    return RecordingViewModel(
      builder: (context, recordingViewModel) {
        if (recordingViewModel.isRecording) {
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
          );
        }
        // 选择模式：显示操作按钮
        if (controller.selectMode) {
          final showReply = controller.selectedEvents.length == 1;
          final isSent = showReply &&
              controller.selectedEvents.first
                  .getDisplayEvent(controller.timeline!)
                  .status
                  .isSent;
          final isError = controller.selectedEvents
              .every((event) => event.status == EventStatus.error);

          return Row(
            children: <Widget>[
              // 删除/转发按钮
              Expanded(
                child: SizedBox(
                  height: height,
                  child: isError
                      ? TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: controller.deleteErrorEventsAction,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.delete_forever_outlined, size: 18),
                              const SizedBox(width: 2),
                              Text(L10n.of(context).delete),
                            ],
                          ),
                        )
                      : TextButton(
                          style: selectedTextButtonStyle,
                          onPressed: controller.forwardEventsAction,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.keyboard_arrow_left_outlined, size: 18),
                              Text(L10n.of(context).forward),
                            ],
                          ),
                        ),
                ),
              ),
              // 复制按钮
              Expanded(
                child: SizedBox(
                  height: height,
                  child: TextButton(
                    style: selectedTextButtonStyle,
                    onPressed: controller.copyEventsAction,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.copy_outlined, size: 18),
                        const SizedBox(width: 2),
                        Text(L10n.of(context).copy),
                      ],
                    ),
                  ),
                ),
              ),
              // 分享按钮
              Expanded(
                child: SizedBox(
                  height: height,
                  child: TextButton(
                    style: selectedTextButtonStyle,
                    onPressed: controller.shareEventsAction,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.share_outlined, size: 18),
                        const SizedBox(width: 2),
                        Text(L10n.of(context).share),
                      ],
                    ),
                  ),
                ),
              ),
              // 回复/重试按钮
              if (showReply)
                Expanded(
                  child: SizedBox(
                    height: height,
                    child: isSent
                        ? TextButton(
                            style: selectedTextButtonStyle,
                            onPressed: controller.replyAction,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(L10n.of(context).reply),
                                const Icon(Icons.keyboard_arrow_right, size: 18),
                              ],
                            ),
                          )
                        : TextButton(
                            style: selectedTextButtonStyle,
                            onPressed: controller.sendAgainAction,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(L10n.of(context).tryToSendAgain),
                                const SizedBox(width: 2),
                                const Icon(Icons.send_outlined, size: 16),
                              ],
                            ),
                          ),
                  ),
                ),
            ],
          );
        }

        // 正常输入模式
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const SizedBox(width: 4),
            AnimatedContainer(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              width: controller.sendController.text.isNotEmpty ? 0 : height,
              height: height,
              alignment: Alignment.center,
              decoration: const BoxDecoration(),
              clipBehavior: Clip.hardEdge,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: () => _showAttachmentBottomSheet(
                  context,
                  controller,
                ),
              ),
            ),
            if (PlatformInfos.isMobile)
              AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                width: controller.sendController.text.isNotEmpty ? 0 : height,
                height: height,
                alignment: Alignment.center,
                decoration: const BoxDecoration(),
                clipBehavior: Clip.hardEdge,
                // 禁用录像功能，点击相机按钮直接拍照
                child: IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () => controller.onAddPopupMenuButtonSelected(
                    AddPopupMenuActions.photoCamera,
                  ),
                  iconSize: height * 0.5,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                // child: PopupMenuButton(
                //   useRootNavigator: true,
                //   icon: const Icon(Icons.camera_alt_outlined),
                //   onSelected: controller.onAddPopupMenuButtonSelected,
                //   iconColor: theme.colorScheme.onPrimaryContainer,
                //   itemBuilder: (context) => [
                //     PopupMenuItem(
                //       value: AddPopupMenuActions.videoCamera,
                //       child: ListTile(
                //         leading: CircleAvatar(
                //           backgroundColor:
                //               theme.colorScheme.onPrimaryContainer,
                //           foregroundColor:
                //               theme.colorScheme.primaryContainer,
                //           child: const Icon(Icons.videocam_outlined),
                //         ),
                //         title: Text(L10n.of(context).recordAVideo),
                //         contentPadding: const EdgeInsets.all(0),
                //       ),
                //     ),
                //     PopupMenuItem(
                //       value: AddPopupMenuActions.photoCamera,
                //       child: ListTile(
                //         leading: CircleAvatar(
                //           backgroundColor:
                //               theme.colorScheme.onPrimaryContainer,
                //           foregroundColor:
                //               theme.colorScheme.primaryContainer,
                //           child: const Icon(Icons.camera_alt_outlined),
                //         ),
                //         title: Text(L10n.of(context).takeAPhoto),
                //         contentPadding: const EdgeInsets.all(0),
                //       ),
                //     ),
                //   ],
                // ),
              ),
            Container(
              height: height,
              width: height,
              alignment: Alignment.center,
              child: IconButton(
                tooltip: L10n.of(context).emojis,
                color: theme.colorScheme.onPrimaryContainer,
                icon: PageTransitionSwitcher(
                  transitionBuilder: (
                    Widget child,
                    Animation<double> primaryAnimation,
                    Animation<double> secondaryAnimation,
                  ) {
                    return SharedAxisTransition(
                      animation: primaryAnimation,
                      secondaryAnimation: secondaryAnimation,
                      transitionType: SharedAxisTransitionType.scaled,
                      fillColor: Colors.transparent,
                      child: child,
                    );
                  },
                  child: Icon(
                    controller.showEmojiPicker
                        ? Icons.keyboard
                        : Icons.add_reaction_outlined,
                    key: ValueKey(controller.showEmojiPicker),
                  ),
                ),
                onPressed: controller.emojiPickerAction,
              ),
            ),
            if (Matrix.of(context).isMultiAccount &&
                Matrix.of(context).hasComplexBundles &&
                Matrix.of(context).currentBundle.length > 1)
              Container(
                height: height,
                width: height,
                alignment: Alignment.center,
                child: _ChatAccountPicker(controller),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 0.0),
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    PasteTextIntent: _PasteFilesAction(controller),
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPendingAttachments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _PendingAttachmentsBar(controller),
                        ),
                      InputBar(
                        room: controller.room,
                        minLines: 1,
                        maxLines: 8,
                        autofocus: !PlatformInfos.isMobile,
                        keyboardType: TextInputType.multiline,
                        textInputAction: AppSettings.sendOnEnter.value == true &&
                                PlatformInfos.isMobile
                            ? TextInputAction.send
                            : null,
                        onSubmitted: controller.onInputBarSubmitted,
                        onContentInserted:
                            controller.handleKeyboardInsertedContent,
                        focusNode: controller.inputFocus,
                        controller: controller.sendController,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.only(
                            left: 6.0,
                            right: 6.0,
                            bottom: 6.0,
                            top: 3.0,
                          ),
                          counter: const SizedBox.shrink(),
                          hintText: L10n.of(context).writeAMessage,
                          hintMaxLines: 1,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          filled: false,
                        ),
                        onChanged: controller.onInputBarChanged,
                        suggestionEmojis: getDefaultEmojiLocale(
                          AppSettings.emojiSuggestionLocale.value.isNotEmpty
                              ? Locale(AppSettings.emojiSuggestionLocale.value)
                              : Localizations.localeOf(context),
                        ).fold(
                          [],
                          (emojis, category) => emojis..addAll(category.emoji),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                height: height,
                width: height,
                alignment: Alignment.center,
                child: AnimatedScale(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurveBounce,
                  scale: controller.sendController.text.isNotEmpty ||
                          hasPendingAttachments
                      ? 1.0
                      : 0.9,
                  child: IconButton(
                    tooltip: L10n.of(context).send,
                    onPressed: controller.send,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.bubbleColor,
                      foregroundColor: theme.onBubbleColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 22),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PendingAttachmentsBar extends StatelessWidget {
  final ChatController controller;

  const _PendingAttachmentsBar(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attachments = controller.pendingAttachments;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.hasCompressiblePendingAttachments)
            Row(
              children: [
                Text(
                  L10n.of(context).compress,
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 8),
                Switch(
                  value: controller.pendingAttachmentsCompress,
                  onChanged: controller.setPendingAttachmentsCompress,
                ),
              ],
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) => _PendingAttachmentItem(
                controller: controller,
                attachment: attachments[index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentItem extends StatelessWidget {
  final ChatController controller;
  final PendingAttachment attachment;

  const _PendingAttachmentItem({
    required this.controller,
    required this.attachment,
  });

  String _displayName() {
    if (attachment.file.name.isNotEmpty) {
      return attachment.file.name;
    }
    if (attachment.file.path.isNotEmpty) {
      return path_lib.basename(attachment.file.path);
    }
    return 'attachment';
  }

  bool _isImage() {
    final path = attachment.file.path.isNotEmpty
        ? attachment.file.path
        : attachment.file.name;
    final mimeType = attachment.file.mimeType ?? lookupMimeType(path);
    return mimeType?.startsWith('image') ?? false;
  }

  Future<String> _ensurePreviewPath() async {
    var path = attachment.file.path;
    if (path.isNotEmpty) return path;

    final bytes = await attachment.file.readAsBytes();
    final tempDir = await getTemporaryDirectory();
    final fileName = _displayName().trim().isEmpty ? 'attachment' : _displayName().trim();
    final tempPath = path_lib.join(
      tempDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$fileName',
    );
    await File(tempPath).writeAsBytes(bytes, flush: true);
    return tempPath;
  }

  Future<void> _openFilePreview(BuildContext context) async {
    if (PlatformInfos.isWeb) return;
    if (_isImage()) {
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: FutureBuilder<Uint8List>(
                  future: attachment.file.readAsBytes(),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const CircularProgressIndicator.adaptive();
                    }
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: L10n.of(context).close,
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final path = await _ensurePreviewPath();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final result = await OpenFile.open(path);
      if (result.type != ResultType.done) {
        final message = result.message.isNotEmpty
            ? result.message
            : L10n.of(context).open;
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(L10n.of(context).open)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    controller.reorderPendingAttachment(
                      attachment,
                      attachment.orderController.text,
                    );
                  }
                },
                child: TextField(
                  controller: attachment.orderController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onTap: () {
                    attachment.orderController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: attachment.orderController.text.length,
                    );
                  },
                  onSubmitted: (value) =>
                      controller.reorderPendingAttachment(attachment, value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.insert_drive_file_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: attachment.captionController,
                    decoration: InputDecoration(
                      hintText: L10n.of(context).optionalMessage,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => _openFilePreview(context),
              tooltip: L10n.of(context).open,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => controller.removePendingAttachment(attachment),
              tooltip: L10n.of(context).remove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(context)
        .currentBundle
        .firstWhere((cl) => cl.userID == mxid, orElse: () => Matrix.of(context).client);
    if (client.userID != mxid) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<Profile>(
        future: controller.sendingClient.fetchOwnProfile(),
        builder: (context, snapshot) => PopupMenuButton<String>(
          useRootNavigator: true,
          onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
          itemBuilder: (BuildContext context) => clients
              .map(
                (client) => PopupMenuItem(
                  value: client.userID,
                  child: FutureBuilder<Profile>(
                    future: client.fetchOwnProfile(),
                    builder: (context, snapshot) => ListTile(
                      leading: Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name: snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 20,
                      ),
                      title: Text(snapshot.data?.displayName ?? client.userID!),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
              )
              .toList(),
          child: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name: snapshot.data?.displayName ??
                Matrix.of(context).client.userID!.localpart,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PasteFilesAction extends ContextAction<PasteTextIntent> {
  _PasteFilesAction(this.controller);

  final ChatController controller;

  @override
  Future<void> invoke(PasteTextIntent intent, [BuildContext? context]) async {
    final Action<PasteTextIntent>? fallback = callingAction;
    if (context != null) {
      final handled = await controller.handlePasteFilesFromClipboard(context);
      if (handled) {
        return;
      }
    }
    fallback?.invoke(intent);
  }

  @override
  bool isEnabled(PasteTextIntent intent, [BuildContext? context]) {
    return callingAction?.isEnabled(intent) ?? false;
  }

  @override
  bool consumesKey(PasteTextIntent intent) {
    return callingAction?.consumesKey(intent) ?? false;
  }
}

/// 显示底部附件选择菜单
void _showAttachmentBottomSheet(
  BuildContext context,
  ChatController controller,
) {
  final l10n = L10n.of(context);
  final theme = Theme.of(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部拖拽指示器
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 20),
            child: Text(
              '选择附件类型',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 发送图像
          _buildAttachmentItem(
            context: context,
            icon: Icons.image_outlined,
            iconColor: const Color(0xFF2196F3),
            iconBgColor: const Color(0xFFE3F2FD),
            title: l10n.sendImage,
            subtitle: '从相册选择图片',
            onTap: () {
              Navigator.pop(context);
              controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.image);
            },
          ),
          const SizedBox(height: 12),
          // 发送文件
          _buildAttachmentItem(
            context: context,
            icon: Icons.attach_file,
            iconColor: const Color(0xFF4CAF50),
            iconBgColor: const Color(0xFFE8F5E9),
            title: l10n.sendFile,
            subtitle: '选择文档或其他文件',
            onTap: () {
              Navigator.pop(context);
              controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.file);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

/// 构建附件列表项
Widget _buildAttachmentItem({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  required Color iconBgColor,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);

  return Material(
    color: theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}
