import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return PopScope(
      canPop: !controller.isSearchMode,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: ChatListViewBody(controller),
                floatingActionButton: !controller.isSearchMode
                    ? FloatingActionButton.extended(
                        onPressed: () => context.go('/rooms/newprivatechat'),
                        icon: const Icon(Icons.add_outlined),
                        label: Text(
                          l10n.chat,
                          overflow: TextOverflow.fade,
                        ),
                      )
                    : const SizedBox.shrink(),
                // Bottom navigation is now handled by MainScreen
              ),
            ),
          ),
        ],
      ),
    );
  }
}
