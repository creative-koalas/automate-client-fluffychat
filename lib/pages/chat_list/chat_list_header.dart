import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_list/chat_list.dart';
import 'package:psygo/pages/chat_list/client_chooser_button.dart';
import 'package:psygo/utils/sync_status_localization.dart';
import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).clientOrNull;

    // Show placeholder if no client is available yet
    if (client == null) {
      return SliverAppBar(
        floating: true,
        toolbarHeight: 72,
        pinned: FluffyThemes.isColumnMode(context),
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                '正在初始化...',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      pinned: FluffyThemes.isColumnMode(context),
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status = client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide = client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) => controller.onSearchEnter(
              text,
              globalSearch: globalSearch,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.secondaryContainer,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(99),
              ),
              contentPadding: EdgeInsets.zero,
              hintText: hide
                  ? L10n.of(context).searchChatsRooms
                  : status.calcLocalizedString(context),
              hintStyle: TextStyle(
                color: status.error != null
                    ? Colors.orange
                    : theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: hide
                  ? controller.isSearchMode
                      ? IconButton(
                          tooltip: L10n.of(context).cancel,
                          icon: const Icon(Icons.close_outlined),
                          onPressed: controller.cancelSearch,
                          color: theme.colorScheme.onPrimaryContainer,
                        )
                      : IconButton(
                          onPressed: controller.startSearch,
                          icon: Icon(
                            Icons.search_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        )
                  : Container(
                      margin: const EdgeInsets.all(12),
                      width: 8,
                      height: 8,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          value: status.progress,
                          valueColor: status.error != null
                              ? const AlwaysStoppedAnimation<Color>(
                                  Colors.orange,
                                )
                              : null,
                        ),
                      ),
                    ),
              // PC端头像功能已移至左侧边栏，这里不再显示
              suffixIcon: controller.isSearchMode && globalSearch
                  ? controller.isSearching
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 10.0,
                            horizontal: 12,
                          ),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : null
                  : FluffyThemes.isColumnMode(context)
                      ? null  // PC端不显示头像
                      : SizedBox(
                          width: 0,
                          child: ClientChooserButton(controller),
                        ),  // 移动端保留头像，使用原有布局
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
