import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'chat.dart';
import 'events/reply_content.dart';

class ReplyDisplay extends StatelessWidget {
  final ChatController controller;
  const ReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReply = controller.replyEvent != null;
    final isEdit = controller.editEvent != null;
    final isVisible = isEdit || isReply;

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 60,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          // 左侧彩色指示条
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isEdit
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 图标
          Icon(
            isEdit ? Icons.edit_rounded : Icons.reply_rounded,
            size: 20,
            color: isEdit
                ? theme.colorScheme.tertiary
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: isReply
                ? ReplyContent(
                    controller.replyEvent!,
                    timeline: controller.timeline!,
                  )
                : _EditContent(
                    controller.editEvent?.getDisplayEvent(controller.timeline!),
                  ),
          ),
          // 关闭按钮
          IconButton(
            tooltip: L10n.of(context).close,
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: controller.cancelReplyEventAction,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _EditContent extends StatelessWidget {
  final Event? event;

  const _EditContent(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = this.event;
    if (event == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          L10n.of(context).edit,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          event.calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
