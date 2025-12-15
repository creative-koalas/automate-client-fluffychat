import 'package:flutter/material.dart';

import 'package:animations/animations.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:matrix/matrix.dart';

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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: controller.selectMode
              ? <Widget>[
                  if (controller.selectedEvents
                      .every((event) => event.status == EventStatus.error))
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: controller.deleteErrorEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.delete_forever_outlined),
                            Text(L10n.of(context).delete),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.forwardEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.keyboard_arrow_left_outlined),
                            Text(L10n.of(context).forward),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(
                    height: height,
                    child: TextButton(
                      style: selectedTextButtonStyle,
                      onPressed: controller.copyEventsAction,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.copy_outlined),
                          const SizedBox(width: 4),
                          Text(L10n.of(context).copy),
                        ],
                      ),
                    ),
                  ),
                  controller.selectedEvents.length == 1
                      ? controller.selectedEvents.first
                              .getDisplayEvent(controller.timeline!)
                              .status
                              .isSent
                          ? SizedBox(
                              height: height,
                              child: TextButton(
                                style: selectedTextButtonStyle,
                                onPressed: controller.replyAction,
                                child: Row(
                                  children: <Widget>[
                                    Text(L10n.of(context).reply),
                                    const Icon(Icons.keyboard_arrow_right),
                                  ],
                                ),
                              ),
                            )
                          : SizedBox(
                              height: height,
                              child: TextButton(
                                style: selectedTextButtonStyle,
                                onPressed: controller.sendAgainAction,
                                child: Row(
                                  children: <Widget>[
                                    Text(L10n.of(context).tryToSendAgain),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.send_outlined, size: 16),
                                  ],
                                ),
                              ),
                            )
                      : const SizedBox.shrink(),
                ]
              : <Widget>[
                  const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    width:
                        controller.sendController.text.isNotEmpty ? 0 : height,
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
                      width: controller.sendController.text.isNotEmpty
                          ? 0
                          : height,
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
                      child: InputBar(
                        room: controller.room,
                        minLines: 1,
                        maxLines: 8,
                        autofocus: !PlatformInfos.isMobile,
                        keyboardType: TextInputType.multiline,
                        textInputAction:
                            AppSettings.sendOnEnter.value == true &&
                                    PlatformInfos.isMobile
                                ? TextInputAction.send
                                : null,
                        onSubmitted: controller.onInputBarSubmitted,
                        onSubmitImage: controller.sendImageFromClipBoard,
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
                    ),
                  ),
                  Container(
                    height: height,
                    width: height,
                    alignment: Alignment.center,
                    child:
                        // 禁用语音消息功能，始终显示发送按钮
                        // PlatformInfos.platformCanRecord &&
                        //         controller.sendController.text.isEmpty
                        //     ? IconButton(
                        //         tooltip: L10n.of(context).voiceMessage,
                        //         onPressed: () =>
                        //             ScaffoldMessenger.of(context).showSnackBar(
                        //           SnackBar(
                        //             content: Text(
                        //               L10n.of(context)
                        //                   .longPressToRecordVoiceMessage,
                        //             ),
                        //           ),
                        //         ),
                        //         onLongPress: () => recordingViewModel
                        //             .startRecording(controller.room),
                        //         style: IconButton.styleFrom(
                        //           backgroundColor: theme.bubbleColor,
                        //           foregroundColor: theme.onBubbleColor,
                        //         ),
                        //         icon: const Icon(Icons.mic_none_outlined),
                        //       )
                        //     :
                        IconButton(
                            tooltip: L10n.of(context).send,
                            onPressed: controller.send,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.bubbleColor,
                              foregroundColor: theme.onBubbleColor,
                            ),
                            icon: const Icon(Icons.send_outlined),
                          ),
                  ),
                ],
        );
      },
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
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
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

