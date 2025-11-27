import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:automate/config/setting_keys.dart';
import 'package:automate/config/themes.dart';
import 'package:automate/l10n/l10n.dart';
import 'package:automate/pages/chat_list/chat_list.dart';
import 'package:automate/widgets/navigation_rail.dart';
import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final showNavigationRail =
        isColumnMode || AppSettings.displayNavigationRail.value;

    return PopScope(
      canPop: !controller.isSearchMode && controller.activeSpaceId == null,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.activeSpaceId != null) {
          controller.clearActiveSpace();
          return;
        }
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          if (showNavigationRail) ...[
            SpacesNavigationRail(
              activeSpaceId: controller.activeSpaceId,
              onGoToChats: controller.clearActiveSpace,
              onGoToSpaceId: controller.setActiveSpace,
            ),
            Container(
              color: theme.dividerColor,
              width: 1,
            ),
          ],
          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: ChatListViewBody(controller),
                floatingActionButton: !controller.isSearchMode &&
                        controller.activeSpaceId == null
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
