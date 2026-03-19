import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_mention_display_name.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import '../../../config/app_config.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;
  final Timeline? timeline;

  const ReplyContent(
    this.replyEvent, {
    this.ownMessage = false,
    super.key,
    this.timeline,
  });

  static const BorderRadius borderRadius = BorderRadius.only(
    topRight: Radius.circular(AppConfig.borderRadius / 2),
    bottomRight: Radius.circular(AppConfig.borderRadius / 2),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent =
        timeline != null ? replyEvent.getDisplayEvent(timeline) : replyEvent;
    final fontSize =
        AppConfig.messageFontSize * AppSettings.fontSizeFactor.value;
    final color = theme.brightness == Brightness.dark
        ? theme.colorScheme.onTertiaryContainer
        : ownMessage
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.tertiary;
    final senderPresentationListenable = Listenable.merge([
      AgentService.instance.agentsNotifier,
      AgentService.instance.profileNotifier,
    ]);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.hardEdge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListenableBuilder(
                  listenable: senderPresentationListenable,
                  builder: (context, _) => FutureBuilder<User?>(
                    initialData: displayEvent.senderFromMemoryOrFallback,
                    future: displayEvent.fetchSenderUser(),
                    builder: (context, snapshot) {
                      final sender = snapshot.data ??
                          displayEvent.senderFromMemoryOrFallback;
                      AgentService.instance.ensureMatrixProfilePresentation(
                        sender,
                      );
                      final senderDisplayName =
                          AgentService.instance.resolveDisplayName(sender);
                      return Text(
                        '$senderDisplayName:',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: fontSize,
                        ),
                      );
                    },
                  ),
                ),
                Text(
                  renderMatrixMentionsWithDisplayName(
                    text: displayEvent.calcLocalizedBodyFallback(
                      MatrixLocals(L10n.of(context)),
                      withSenderNamePrefix: false,
                      hideReply: true,
                    ),
                    room: displayEvent.room,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.onSurface
                        : ownMessage
                            ? theme.colorScheme.onTertiary
                            : theme.colorScheme.onSurface,
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
