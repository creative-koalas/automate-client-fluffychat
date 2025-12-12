import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_details/chat_details_view.dart';
import 'package:psygo/pages/settings/settings.dart';
import 'package:psygo/utils/file_selector.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/matrix.dart';

enum AliasActions { copy, delete, setCanonical }

class ChatDetails extends StatefulWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
  });

  @override
  ChatDetailsController createState() => ChatDetailsController();
}

class ChatDetailsController extends State<ChatDetails> {
  bool displaySettings = false;

  void toggleDisplaySettings() =>
      setState(() => displaySettings = !displaySettings);

  String? get roomId => widget.roomId;

  void setDisplaynameAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).changeTheNameOfTheGroup,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: room.getLocalizedDisplayname(
        MatrixLocals(
          L10n.of(context),
        ),
      ),
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).displaynameHasBeenChanged)),
      );
    }
  }

  void setTopicAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).setChatDescription,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).chatDescriptionHasBeenChanged),
        ),
      );
    }
  }

  static const fixedWidth = 360.0;

  @override
  Widget build(BuildContext context) => ChatDetailsView(this);
}
