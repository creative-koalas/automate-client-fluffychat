import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  Widget _buildEnhancedFAB(BuildContext context, L10n l10n) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () => context.go('/rooms/newprivatechat'),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        elevation: 0,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          l10n.chat,
          overflow: TextOverflow.fade,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

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
                    ? _buildEnhancedFAB(context, l10n)
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
