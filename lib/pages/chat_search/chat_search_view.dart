import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/chat_search/chat_search_files_tab.dart';
import 'package:psygo/pages/chat_search/chat_search_images_tab.dart';
import 'package:psygo/pages/chat_search/chat_search_message_tab.dart';
import 'package:psygo/pages/chat_search/chat_search_page.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';

class ChatSearchView extends StatelessWidget {
  final ChatSearchController controller;

  const ChatSearchView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        titleSpacing: 0,
        title: Text(
          L10n.of(context).searchIn(
            room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
          ),
        ),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        child: Column(
          children: [
            if (FluffyThemes.isThreeColumnMode(context))
              const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withAlpha(15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: controller.searchController,
                  onSubmitted: (_) => controller.restartSearch(),
                  autofocus: true,
                  enabled: controller.tabController.index == 0,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: L10n.of(context).search,
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.search_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 46,
                      minHeight: 46,
                    ),
                    suffixIcon: controller.searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              controller.searchController.clear();
                              controller.restartSearch();
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(180),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withAlpha(30),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(100),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                      fontWeight: FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
            TabBar(
              controller: controller.tabController,
              tabs: [
                Tab(child: Text(L10n.of(context).messages)),
                Tab(child: Text(L10n.of(context).gallery)),
                Tab(child: Text(L10n.of(context).files)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: controller.tabController,
                children: [
                  ChatSearchMessageTab(
                    searchQuery: controller.searchController.text,
                    room: room,
                    startSearch: controller.startMessageSearch,
                    searchStream: controller.searchStream,
                  ),
                  ChatSearchImagesTab(
                    room: room,
                    startSearch: controller.startGallerySearch,
                    searchStream: controller.galleryStream,
                  ),
                  ChatSearchFilesTab(
                    room: room,
                    startSearch: controller.startFileSearch,
                    searchStream: controller.fileStream,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
