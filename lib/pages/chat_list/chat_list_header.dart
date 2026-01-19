import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/setting_keys.dart';
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

    final isDesktop = FluffyThemes.isColumnMode(context);
    // PC 端：搜索框 + 筛选按钮都固定在头部
    final showFilterChips =
        isDesktop && client.rooms.isNotEmpty && !controller.isSearchMode;

    return SliverAppBar(
      floating: true,
      toolbarHeight: showFilterChips ? 120 : 72,
      pinned: isDesktop,
      scrolledUnderElevation: 0,
      // PC 端设置背景色，防止滚动时内容透出
      backgroundColor:
          isDesktop ? theme.scaffoldBackgroundColor : Colors.transparent,
      automaticallyImplyLeading: false,
      flexibleSpace: isDesktop
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.04),
                    theme.scaffoldBackgroundColor,
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.03),
                  ],
                ),
              ),
            )
          : null,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 搜索框
          StreamBuilder(
            stream: client.onSyncStatus.stream,
            builder: (context, snapshot) {
              final status = client.onSyncStatus.value ??
                  const SyncStatusUpdate(SyncStatus.waitingForResponse);
              final hide = client.onSync.value != null &&
                  status.status != SyncStatus.error &&
                  client.prevBatch != null;
              return AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: controller.isSearchMode
                        ? [
                            theme.colorScheme.primaryContainer.withValues(alpha: 0.12),
                            theme.colorScheme.surfaceContainerHigh,
                          ]
                        : [
                            theme.colorScheme.surfaceContainerHigh,
                            theme.colorScheme.surfaceContainer.withValues(alpha: 0.8),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: controller.isSearchMode
                      ? Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                          width: 1.5,
                        )
                      : Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.1),
                          width: 1,
                        ),
                  boxShadow: controller.isSearchMode
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.08),
                            blurRadius: 12,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: theme.colorScheme.shadow.withAlpha(8),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withAlpha(4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: TextField(
                  controller: controller.searchController,
                  focusNode: controller.searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: (text) => controller.onSearchEnter(
                    text,
                    globalSearch: globalSearch,
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                    hintText: hide
                        ? L10n.of(context).searchChatsRooms
                        : status.calcLocalizedString(context),
                    hintStyle: TextStyle(
                      color: status.error != null
                          ? Colors.orange
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                    ),
                    prefixIcon: hide
                        ? AnimatedSwitcher(
                            duration: FluffyThemes.animationDuration,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: controller.isSearchMode
                                ? IconButton(
                                    key: const ValueKey('close'),
                                    tooltip: L10n.of(context).cancel,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    onPressed: controller.cancelSearch,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )
                                : IconButton(
                                    key: const ValueKey('search'),
                                    onPressed: controller.startSearch,
                                    icon: Icon(
                                      Icons.search_rounded,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: status.progress,
                                valueColor: status.error != null
                                    ? const AlwaysStoppedAnimation<Color>(
                                        Colors.orange,
                                      )
                                    : AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.primary,
                                      ),
                              ),
                            ),
                          ),
                    suffixIcon: controller.isSearchMode && globalSearch
                        ? controller.isSearching
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                            : null
                        : isDesktop
                            ? null
                            : SizedBox(
                                width: 0,
                                child: ClientChooserButton(controller),
                              ),
                  ),
                ),
              );
            },
          ),
          // PC 端筛选按钮：均匀分布占满宽度
          if (showFilterChips)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  ...[
                    if (AppSettings.separateChatTypes.value)
                      ActiveFilter.messages
                    else
                      ActiveFilter.allChats,
                    ActiveFilter.groups,
                    ActiveFilter.unread,
                  ].map(
                    (filter) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: FilterChip(
                          selected: filter == controller.activeFilter,
                          onSelected: (_) => controller.setActiveFilter(filter),
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              filter.toLocalizedString(context),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
