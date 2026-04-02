import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:badges/badges.dart' as badges;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:matrix/matrix.dart';
import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/models/agent.dart';
import 'package:psygo/pages/chat/chat.dart';
import 'package:psygo/pages/chat/chat_app_bar_list_tile.dart';
import 'package:psygo/pages/chat/chat_app_bar_title.dart';
import 'package:psygo/pages/chat/chat_event_list.dart';
import 'package:psygo/pages/chat/pinned_events.dart';
import 'package:psygo/pages/chat/reply_display.dart';
import 'package:psygo/repositories/agent_repository.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/account_config.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/widgets/chat_settings_popup_menu.dart';
import 'package:psygo/widgets/employee_work_template_bar.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/agent_web_entry_view.dart';
import 'package:psygo/widgets/chat_room_intro_guide.dart';
import 'package:psygo/widgets/guide_bubble_layout.dart';
import 'package:psygo/widgets/matrix.dart';
import 'package:psygo/widgets/mxc_image.dart';
import 'package:psygo/widgets/unread_rooms_badge.dart';
import 'package:psygo/utils/platform_infos.dart';
import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';
import 'employee_working_indicator.dart';

enum _EventContextAction { info, report }

class _CaptureScreenshotIntent extends Intent {
  const _CaptureScreenshotIntent();
}

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  Widget _buildWebEntryActionButton(
    BuildContext context, {
    required Agent agent,
    required bool isVisuallyDisabled,
  }) {
    final l10n = L10n.of(context);
    final isUpdated = agent.webEntryStatus == Agent.webEntryStatusUpdated &&
        !isVisuallyDisabled;
    final isEnabled = agent.webEntryStatus == Agent.webEntryStatusEnabled &&
        !isVisuallyDisabled;

    return _WebEntryActionButton(
      key: controller.webEntryGuideKey,
      isOpen: controller.webEntryOpen,
      isLoading: controller.webEntryLoading,
      isDisabled: isVisuallyDisabled,
      isEnabled: isEnabled,
      isUpdated: isUpdated,
      unavailableTooltip: l10n.agentWebEntryUnavailable,
      onPressed: controller.webEntryOpen || controller.webEntryLoading
          ? controller.closeWebEntry
          : controller.openWebEntry,
    );
  }

  Widget _buildGuideStatusItem(
    BuildContext context, {
    required Color color,
    required String label,
    required String hint,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$label：',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: hint),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatRoomGuide(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final steps = controller.isGroupMentionGuide
        ? <ChatRoomIntroGuideStep>[
            ChatRoomIntroGuideStep(
              targetKey: controller.mentionGuideKey,
              title: l10n.chatRoomGuideMentionTitle,
              description: l10n.chatRoomGuideMentionBody,
              preferredPlacement: GuideBubblePlacement.above,
            ),
          ]
        : <ChatRoomIntroGuideStep>[
            ChatRoomIntroGuideStep(
              targetKey: controller.workStatusGuideKey,
              title: l10n.chatRoomGuideWorkStatusTitle,
              description: l10n.chatRoomGuideWorkStatusBody,
              preferredPlacement: GuideBubblePlacement.below,
              estimatedContentHeight: 120,
              contentBuilder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGuideStatusItem(
                    context,
                    color: theme.colorScheme.tertiary,
                    label: l10n.employeeWorking,
                    hint: l10n.employeeWorkingHint,
                  ),
                  const SizedBox(height: 10),
                  _buildGuideStatusItem(
                    context,
                    color: theme.colorScheme.primary,
                    label: l10n.employeeSlacking,
                    hint: l10n.employeeSlackingHint,
                  ),
                  const SizedBox(height: 10),
                  _buildGuideStatusItem(
                    context,
                    color: theme.colorScheme.outline,
                    label: l10n.employeeSleeping,
                    hint: l10n.employeeSleepingHint,
                  ),
                ],
              ),
            ),
            ChatRoomIntroGuideStep(
              targetKey: controller.webEntryGuideKey,
              title: l10n.chatRoomGuideSmartInterfaceTitle,
              description: l10n.chatRoomGuideSmartInterfaceBody,
              preferredPlacement: GuideBubblePlacement.below,
            ),
            ChatRoomIntroGuideStep(
              targetKey: controller.webEntryGuideKey,
              title: l10n.chatRoomGuideWebEntryTitle,
              description: l10n.chatRoomGuideWebEntryBody,
              preferredPlacement: GuideBubblePlacement.below,
            ),
            ChatRoomIntroGuideStep(
              targetKey: controller.employeeWorkTemplateGuideKey,
              title: l10n.chatRoomGuideWorkTemplateTitle,
              description: l10n.chatRoomGuideWorkTemplateBody,
              preferredPlacement: GuideBubblePlacement.below,
            ),
          ];

    return ChatRoomIntroGuide(
      visible: controller.showChatRoomGuide,
      containerKey: controller.chatRoomGuideContainerKey,
      steps: steps,
      currentStepIndex: controller.chatRoomGuideStepIndex,
      showStepCounter: !controller.isGroupMentionGuide,
      onPrimaryAction: controller.nextChatRoomGuideStep,
      primaryActionLabel: controller.chatRoomGuideStepIndex >= steps.length - 1
          ? l10n.confirm
          : l10n.next,
    );
  }

  static IconData _iconForEmployeeWorkTemplateId(String templateId) {
    switch (templateId.trim()) {
      case 'bmi_calculator_ui':
        return Icons.today_outlined;
      case 'bnct_heavy_ion_report':
        return Icons.notes_rounded;
      case 'godot_tower_defense_game':
        return Icons.sports_esports_rounded;
      case 'daily_ai_briefing':
        return Icons.newspaper_rounded;
      default:
        return Icons.assignment_rounded;
    }
  }

  List<EmployeeWorkTemplateItem> _defaultEmployeeWorkTemplates(
    BuildContext context,
  ) {
    final l10n = L10n.of(context);
    return [
      EmployeeWorkTemplateItem(
        icon: Icons.today_outlined,
        title: l10n.employeeWorkTemplatePlanTitle,
        description: l10n.employeeWorkTemplatePlanDescription,
        message: l10n.employeeWorkTemplatePlanMessage,
      ),
      EmployeeWorkTemplateItem(
        icon: Icons.notes_rounded,
        title: l10n.employeeWorkTemplateSummaryTitle,
        description: l10n.employeeWorkTemplateSummaryDescription,
        message: l10n.employeeWorkTemplateSummaryMessage,
      ),
      EmployeeWorkTemplateItem(
        icon: Icons.sports_esports_rounded,
        title: l10n.employeeWorkTemplateIssueTitle,
        description: l10n.employeeWorkTemplateIssueDescription,
        message: l10n.employeeWorkTemplateIssueMessage,
      ),
      EmployeeWorkTemplateItem(
        icon: Icons.newspaper_rounded,
        title: l10n.employeeWorkTemplateDailyTitle,
        description: l10n.employeeWorkTemplateDailyDescription,
        message: l10n.employeeWorkTemplateDailyMessage,
      ),
    ];
  }

  List<EmployeeWorkTemplateItem> _employeeWorkTemplates(BuildContext context) {
    if (controller.employeeWorkTemplates.isNotEmpty) {
      return controller.employeeWorkTemplates
          .where((template) => template.enabled)
          .map(
            (template) => EmployeeWorkTemplateItem(
              icon: _iconForEmployeeWorkTemplateId(template.templateId),
              title: template.title,
              description: template.description,
              message: template.message,
            ),
          )
          .toList(growable: false);
    }
    return _defaultEmployeeWorkTemplates(context);
  }

  Future<void> _handleEmployeeWorkTemplateTap(
    BuildContext context,
    EmployeeWorkTemplateItem template,
  ) async {
    final l10n = L10n.of(context);
    final shouldSend = await showEmployeeWorkTemplatePreviewDialog(
      context: context,
      template: template,
      previewLabel: l10n.employeeWorkTemplatePreviewLabel,
      sendLabel: l10n.send,
      cancelLabel: l10n.cancel,
    );
    if (shouldSend == true) {
      controller.sendEmployeeWorkTemplateMessage(template.message);
    }
  }

  EmployeeWorkTemplateBar _buildEmployeeWorkTemplateBar(
    BuildContext context, {
    Key? key,
    EdgeInsetsGeometry? margin,
    VoidCallback? onClose,
  }) {
    final l10n = L10n.of(context);
    return EmployeeWorkTemplateBar(
      key: key,
      title: l10n.employeeWorkTemplatesTitle,
      subtitle: l10n.employeeWorkTemplatesSubtitle,
      templates: _employeeWorkTemplates(context),
      onTemplateTap: (template) =>
          _handleEmployeeWorkTemplateTap(context, template),
      margin: margin,
      onClose: onClose,
    );
  }

  Widget _buildTimelinePane(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = PlatformInfos.isDesktop;
    final templateMargin = EdgeInsets.fromLTRB(
      isDesktop ? 16 : 12,
      isDesktop ? 6 : 2,
      isDesktop ? 16 : 12,
      8,
    );
    final showEmployeeWorkTemplateBar =
        controller.isEmployeeChat &&
        controller.activeThreadId == null &&
        !controller.employeeWorkTemplateDismissed;
    final onCloseEmployeeWorkTemplate =
        controller.canDismissEmployeeWorkTemplateBar
        ? controller.dismissEmployeeWorkTemplateBar
        : null;
    final employeeWorkTemplateBar = showEmployeeWorkTemplateBar
        ? _buildEmployeeWorkTemplateBar(
            context,
            key: controller.employeeWorkTemplateGuideKey,
            margin: templateMargin,
            onClose: onCloseEmployeeWorkTemplate,
          )
        : null;

    return Column(
      children: [
        if (employeeWorkTemplateBar != null) employeeWorkTemplateBar,
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                onTap: controller.clearSingleSelectedEvent,
                child: ChatEventList(controller: controller),
              ),
              if (controller.readMarkerEventId.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: controller.scrollToReadMarker,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_upward,
                              size: 16,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.of(context).newMessages,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _appBarActions(BuildContext context) {
    if (controller.selectMode) {
      return [
        if (controller.canEditSelectedEvents)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: L10n.of(context).edit,
            onPressed: controller.editSelectedEventAction,
          ),
        if (controller.selectedEvents.length == 1 &&
            controller.activeThreadId == null &&
            controller.room.canSendDefaultMessages)
          IconButton(
            icon: const Icon(Icons.message_outlined),
            tooltip: L10n.of(context).replyInThread,
            onPressed: () => controller.enterThread(
              controller.selectedEvents.single.eventId,
            ),
          ),
        if (controller.canPinSelectedEvents)
          IconButton(
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: controller.pinEvent,
            tooltip: L10n.of(context).pinMessage,
          ),
        if (controller.canRedactSelectedEvents)
          IconButton(
            icon: const Icon(Icons.delete_outlined),
            tooltip: L10n.of(context).redactMessage,
            onPressed: controller.redactEventsAction,
          ),
        if (controller.selectedEvents.length == 1)
          PopupMenuButton<_EventContextAction>(
            useRootNavigator: true,
            onSelected: (action) {
              switch (action) {
                case _EventContextAction.info:
                  controller.showEventInfo();
                  controller.clearSelectedEvents();
                  break;
                case _EventContextAction.report:
                  controller.reportEventAction();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (controller.canSaveSelectedEvent)
                PopupMenuItem(
                  onTap: () => controller.saveSelectedEvent(context),
                  value: null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_outlined),
                      const SizedBox(width: 12),
                      Text(L10n.of(context).downloadFile),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: _EventContextAction.info,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).messageInfo),
                  ],
                ),
              ),
              if (controller.selectedEvents.single.status.isSent)
                PopupMenuItem(
                  value: _EventContextAction.report,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(L10n.of(context).reportMessage),
                    ],
                  ),
                ),
            ],
          ),
      ];
    } else if (!controller.room.isArchived) {
      final directChatMatrixID = controller.room.directChatMatrixID;
      return [
        if (directChatMatrixID != null)
          ValueListenableBuilder<List<Agent>>(
            valueListenable: AgentService.instance.agentsNotifier,
            builder: (context, _, __) {
              final agent = AgentService.instance.getAgentByMatrixUserId(
                directChatMatrixID,
              );
              if (agent == null) return const SizedBox.shrink();
              final isDisabled = !controller.webEntryOpen &&
                  !controller.webEntryLoading &&
                  !agent.canOpenWebEntry;
              final isVisuallyDisabled = isDisabled || agent.isResting;

              return _buildWebEntryActionButton(
                context,
                agent: agent,
                isVisuallyDisabled: isVisuallyDisabled,
              );
            },
          ),
        if (AppSettings.experimentalVoip.value &&
            Matrix.of(context).voipPlugin != null &&
            controller.room.isDirectChat)
          IconButton(
            onPressed: controller.onPhoneButtonTap,
            icon: const Icon(Icons.call_outlined),
            tooltip: L10n.of(context).placeCall,
          ),
        ChatSettingsPopupMenu(controller.room, true),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.room.membership == Membership.invite) {
      showFutureLoadingDialog(
        context: context,
        future: () => controller.room.join(),
        exceptionContext: ExceptionContext.joinRoom,
      );
    }
    final bottomSheetPadding = FluffyThemes.isColumnMode(context) ? 16.0 : 8.0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final sendModeSwitchWidth =
        (viewportWidth * 0.12).clamp(40.0, 56.0).toDouble();
    final sendModeSwitchHeight = (sendModeSwitchWidth * 0.58)
        .clamp(22.0, 30.0)
        .toDouble();
    final sendModeSwitchRightInset =
        ((viewportWidth * 0.035) - 5.0).clamp(6.0, 21.0).toDouble();
    final sendModeSwitchPadding = (sendModeSwitchHeight * 0.12)
        .clamp(2.0, 4.0)
        .toDouble();
    final sendModeSwitchRadius = sendModeSwitchHeight / 2;
    final sendModeSwitchKnobSize =
        sendModeSwitchHeight - (sendModeSwitchPadding * 2);
    final sendModeSwitchTrackIconSize = (sendModeSwitchHeight * 0.45)
        .clamp(10.0, 14.0)
        .toDouble();
    final sendModeSwitchKnobIconSize = (sendModeSwitchKnobSize * 0.58)
        .clamp(10.0, 14.0)
        .toDouble();
    final shouldShowGroupSendSwitch =
        controller.isGroupChat &&
        controller.selectedEvents.isEmpty &&
        controller.room.isAbandonedDMRoom != true;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop:
          controller.selectedEvents.isEmpty &&
          !controller.showEmojiPicker &&
          controller.activeThreadId == null &&
          !controller.webEntryOpen &&
          !controller.webEntryLoading,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.webEntryOpen || controller.webEntryLoading) {
          controller.closeWebEntry();
        } else if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        } else if (controller.activeThreadId != null) {
          controller.closeThread();
        }
      },
      child: Shortcuts(
        shortcuts: PlatformInfos.isMacOS
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.keyS, meta: true, alt: true):
                    _CaptureScreenshotIntent(),
              }
            : const <ShortcutActivator, Intent>{},
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CaptureScreenshotIntent: CallbackAction<_CaptureScreenshotIntent>(
              onInvoke: (_) {
                controller.captureScreenshotAction();
                return null;
              },
            ),
          },
          child: StreamBuilder(
            stream: controller.room.client.onRoomState.stream
                .where((update) => update.roomId == controller.room.id)
                .rateLimit(const Duration(seconds: 1)),
            builder: (context, snapshot) => FutureBuilder(
              future: controller.loadTimelineFuture,
              builder: (BuildContext context, snapshot) {
                var appbarBottomHeight = 0.0;
                final activeThreadId = controller.activeThreadId;
                if (activeThreadId != null) {
                  appbarBottomHeight += ChatAppBarListTile.fixedHeight;
                }
                if (controller.room.pinnedEventIds.isNotEmpty &&
                    activeThreadId == null) {
                  appbarBottomHeight += ChatAppBarListTile.fixedHeight;
                }
                if (scrollUpBannerEventId != null && activeThreadId == null) {
                  appbarBottomHeight += ChatAppBarListTile.fixedHeight;
                }
                return Stack(
                  key: controller.chatRoomGuideContainerKey,
                  children: [
                    Scaffold(
                      appBar: AppBar(
                        actionsIconTheme: IconThemeData(
                          color: controller.selectedEvents.isEmpty
                              ? null
                              : theme.colorScheme.onTertiaryContainer,
                        ),
                        backgroundColor: controller.selectedEvents.isEmpty
                            ? controller.activeThreadId != null
                                  ? theme.colorScheme.secondaryContainer
                                  : null
                            : theme.colorScheme.tertiaryContainer,
                        automaticallyImplyLeading: false,
                        leading: controller.selectMode
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: controller.clearSelectedEvents,
                                tooltip: L10n.of(context).close,
                                color: theme.colorScheme.onTertiaryContainer,
                              )
                            : activeThreadId != null
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: controller.closeThread,
                                tooltip: L10n.of(context).backToMainChat,
                                color: theme.colorScheme.onSecondaryContainer,
                              )
                            : FluffyThemes.isColumnMode(context)
                            ? null
                            : StreamBuilder<Object>(
                                stream: Matrix.of(context).client.onSync.stream
                                    .where(
                                      (syncUpdate) => syncUpdate.hasRoomUpdate,
                                    ),
                                builder: (context, _) => UnreadRoomsBadge(
                                  filter: (r) => r.id != controller.roomId,
                                  badgePosition: badges.BadgePosition.topEnd(
                                    end: 8,
                                    top: 4,
                                  ),
                                  child: const Center(child: BackButton()),
                                ),
                              ),
                        titleSpacing: FluffyThemes.isColumnMode(context)
                            ? 24
                            : 0,
                        title: ChatAppBarTitle(controller),
                        actions: _appBarActions(context),
                        bottom: PreferredSize(
                          preferredSize: Size.fromHeight(appbarBottomHeight),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PinnedEvents(controller),
                              if (activeThreadId != null)
                                SizedBox(
                                  height: ChatAppBarListTile.fixedHeight,
                                  child: Center(
                                    child: TextButton.icon(
                                      onPressed: () => controller
                                          .scrollToEventId(activeThreadId),
                                      icon: const Icon(Icons.message),
                                      label: Text(
                                        L10n.of(context).replyInThread,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: theme
                                            .colorScheme
                                            .onSecondaryContainer,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (scrollUpBannerEventId != null &&
                                  activeThreadId == null)
                                ChatAppBarListTile(
                                  leading: IconButton(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    icon: const Icon(Icons.close),
                                    tooltip: L10n.of(context).close,
                                    onPressed: () {
                                      controller.discardScrollUpBannerEventId();
                                      controller.setReadMarker();
                                    },
                                  ),
                                  title: L10n.of(context).jumpToLastReadMessage,
                                  trailing: TextButton(
                                    onPressed: () {
                                      controller.scrollToEventId(
                                        scrollUpBannerEventId,
                                      );
                                      controller.discardScrollUpBannerEventId();
                                    },
                                    child: Text(L10n.of(context).jump),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      floatingActionButtonLocation:
                          FloatingActionButtonLocation.miniCenterFloat,
                      floatingActionButton:
                          controller.showScrollDownButton &&
                              controller.selectedEvents.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 56.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
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
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: FloatingActionButton(
                                  onPressed: controller.scrollDown,
                                  heroTag: null,
                                  mini: true,
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: theme.colorScheme.primary,
                                  elevation: 0,
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            )
                          : null,
                      body: DropTarget(
                        onDragDone: controller.onDragDone,
                        onDragEntered: controller.onDragEntered,
                        onDragExited: controller.onDragExited,
                        child: Stack(
                          children: <Widget>[
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: accountConfig.wallpaperOpacity ?? 0.5,
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: accountConfig.wallpaperBlur ?? 0.0,
                                    sigmaY: accountConfig.wallpaperBlur ?? 0.0,
                                  ),
                                  child: MxcImage(
                                    cacheKey: accountConfig.wallpaperUrl
                                        .toString(),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    height: MediaQuery.sizeOf(context).height,
                                    width: MediaQuery.sizeOf(context).width,
                                    isThumbnail: false,
                                    placeholder: (_) => Container(),
                                  ),
                                ),
                              ),
                            SafeArea(
                              child: Column(
                                children: <Widget>[
                                  Expanded(
                                    child:
                                        controller.webEntryOpen &&
                                            controller.webEntryUrl != null
                                        ? AgentWebEntryView(
                                            url: controller.webEntryUrl!,
                                          )
                                        : _buildTimelinePane(context),
                                  ),
                                  if (controller.showScrollDownButton)
                                    Divider(
                                      height: 1,
                                      color: theme.dividerColor,
                                    ),
                                  if (controller.room.isExtinct)
                                    Container(
                                      margin: EdgeInsets.all(
                                        bottomSheetPadding,
                                      ),
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.chevron_right),
                                        label: Text(
                                          L10n.of(context).enterNewChat,
                                        ),
                                        onPressed: controller.goToNewRoomAction,
                                      ),
                                    )
                                  else if (controller
                                          .room
                                          .canSendDefaultMessages &&
                                      controller.room.membership ==
                                          Membership.join)
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          margin: PlatformInfos.isDesktop
                                              ? EdgeInsets.only(
                                                  top: bottomSheetPadding,
                                                  left: 60.0,
                                                  right: 60.0,
                                                  bottom: 4, // 减小底部间距
                                                )
                                              : EdgeInsets.only(
                                                  top: bottomSheetPadding,
                                                  left: bottomSheetPadding,
                                                  right: bottomSheetPadding,
                                                  bottom: 4, // 减小底部间距
                                                ),
                                          constraints: PlatformInfos.isDesktop
                                              ? null // PC 端不限制宽度，动态适应
                                              : const BoxConstraints(
                                                  maxWidth: FluffyThemes
                                                      .maxTimelineWidth,
                                                ),
                                          alignment: PlatformInfos.isDesktop
                                              ? null // PC 端不居中
                                              : Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: ValueListenableBuilder(
                                                      valueListenable:
                                                          AgentService
                                                              .instance
                                                              .agentsNotifier,
                                                      builder:
                                                          (
                                                            context,
                                                            _,
                                                            __,
                                                          ) =>
                                                              EmployeeWorkingIndicator(
                                                                controller,
                                                              ),
                                                    ),
                                                  ),
                                                  if (shouldShowGroupSendSwitch)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        right:
                                                            sendModeSwitchRightInset,
                                                      ),
                                                      child: Tooltip(
                                                        message: controller
                                                                .groupSendShouldPromptMention
                                                            ? L10n.of(context)
                                                                .mentionHintTitle
                                                            : L10n.of(context)
                                                                .sendDirectly,
                                                        child: GestureDetector(
                                                          behavior:
                                                              HitTestBehavior
                                                                  .opaque,
                                                          onTap: controller
                                                              .toggleGroupSendMode,
                                                          child:
                                                              AnimatedContainer(
                                                            duration: FluffyThemes
                                                                .durationFast,
                                                            curve: FluffyThemes
                                                                .curveStandard,
                                                            width:
                                                                sendModeSwitchWidth,
                                                            height:
                                                                sendModeSwitchHeight,
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      sendModeSwitchPadding,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: theme
                                                                  .colorScheme
                                                                  .surfaceContainerHigh,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                        sendModeSwitchRadius,
                                                                      ),
                                                              border: Border.all(
                                                                color: theme
                                                                    .colorScheme
                                                                    .outlineVariant,
                                                              ),
                                                            ),
                                                            child: Stack(
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              children: [
                                                                Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .spaceBetween,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .alternate_email_rounded,
                                                                      size:
                                                                          sendModeSwitchTrackIconSize,
                                                                      color: theme
                                                                          .colorScheme
                                                                          .onSurfaceVariant,
                                                                    ),
                                                                    Icon(
                                                                      Icons
                                                                          .send_rounded,
                                                                      size:
                                                                          sendModeSwitchTrackIconSize,
                                                                      color: theme
                                                                          .colorScheme
                                                                          .onSurfaceVariant,
                                                                    ),
                                                                  ],
                                                                ),
                                                                AnimatedAlign(
                                                                  duration:
                                                                      FluffyThemes
                                                                          .durationFast,
                                                                  curve: FluffyThemes
                                                                      .curveBounce,
                                                                  alignment:
                                                                      controller.groupSendShouldPromptMention
                                                                      ? Alignment
                                                                            .centerLeft
                                                                      : Alignment
                                                                            .centerRight,
                                                                  child:
                                                                      Container(
                                                                    width:
                                                                        sendModeSwitchKnobSize,
                                                                    height:
                                                                        sendModeSwitchKnobSize,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: theme
                                                                          .colorScheme
                                                                          .primary,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            sendModeSwitchKnobSize /
                                                                                2,
                                                                          ),
                                                                    ),
                                                                    child: Icon(
                                                                      controller.groupSendShouldPromptMention
                                                                          ? Icons.alternate_email_rounded
                                                                          : Icons.send_rounded,
                                                                      size:
                                                                          sendModeSwitchKnobIconSize,
                                                                      color: theme
                                                                          .colorScheme
                                                                          .onPrimary,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (controller
                                                      .hasOwnEmployeeInRoom &&
                                                  controller
                                                          .room
                                                          .isAbandonedDMRoom !=
                                                      true)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                  child: ChatQuickTipsBar(
                                                    controller,
                                                  ),
                                                ),
                                              Material(
                                                clipBehavior: Clip.hardEdge,
                                                color:
                                                    controller
                                                        .selectedEvents
                                                        .isNotEmpty
                                                    ? theme
                                                          .colorScheme
                                                          .tertiaryContainer
                                                    : theme
                                                          .colorScheme
                                                          .surfaceContainerHigh,
                                                borderRadius:
                                                    const BorderRadius.all(
                                                      Radius.circular(24),
                                                    ),
                                                child:
                                                    controller
                                                            .room
                                                            .isAbandonedDMRoom ==
                                                        true
                                                    ? Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceEvenly,
                                                        children: [
                                                          TextButton.icon(
                                                            style: TextButton.styleFrom(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    16,
                                                                  ),
                                                              foregroundColor:
                                                                  theme
                                                                      .colorScheme
                                                                      .error,
                                                            ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .archive_outlined,
                                                            ),
                                                            onPressed:
                                                                controller
                                                                    .leaveChat,
                                                            label: Text(
                                                              L10n.of(
                                                                context,
                                                              ).declineInvitation,
                                                            ),
                                                          ),
                                                          TextButton.icon(
                                                            style: TextButton.styleFrom(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    16,
                                                                  ),
                                                            ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .forum_outlined,
                                                            ),
                                                            onPressed:
                                                                controller
                                                                    .recreateChat,
                                                            label: Text(
                                                              L10n.of(
                                                                context,
                                                              ).reopenChat,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          ReplyDisplay(
                                                            controller,
                                                          ),
                                                          ChatInputRow(
                                                            controller,
                                                          ),
                                                          ChatEmojiPicker(
                                                            controller,
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                              // AI 内容免责声明（在 Material 外面，但在 Container margin 里面）
                                              _AiContentDisclaimer(
                                                room: controller.room,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (controller.dragging)
                              Container(
                                color: theme.scaffoldBackgroundColor.withAlpha(
                                  230,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.upload_outlined,
                                  size: 100,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _buildChatRoomGuide(context),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WebEntryActionButton extends StatefulWidget {
  final bool isOpen;
  final bool isLoading;
  final bool isDisabled;
  final bool isEnabled;
  final bool isUpdated;
  final String unavailableTooltip;
  final VoidCallback onPressed;

  const _WebEntryActionButton({
    super.key,
    required this.isOpen,
    required this.isLoading,
    required this.isDisabled,
    required this.isEnabled,
    required this.isUpdated,
    required this.unavailableTooltip,
    required this.onPressed,
  });

  @override
  State<_WebEntryActionButton> createState() => _WebEntryActionButtonState();
}

class _WebEntryActionButtonState extends State<_WebEntryActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _WebEntryActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isUpdated) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUnavailable = widget.isDisabled && !widget.isOpen;
    final isHighlighted =
        !widget.isDisabled && !widget.isOpen && widget.isUpdated;
    final enabledStyle = _resolveEnabledStyle(colorScheme);
    final updatedStyle = _resolveUpdatedStyle(colorScheme, enabledStyle);
    final disabledStyle = _resolveDisabledStyle(colorScheme);
    final stateStyle = widget.isUpdated
        ? updatedStyle
        : widget.isEnabled
            ? enabledStyle
            : disabledStyle;
    final highlightColor = stateStyle.accent;
    final baseBackground = widget.isOpen
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.16)
        : widget.isUpdated
            ? updatedStyle.background
            : widget.isEnabled
                ? enabledStyle.background
                : disabledStyle.background;

    final tooltip = widget.isOpen
        ? '返回聊天'
        : widget.isDisabled
            ? widget.unavailableTooltip
            : widget.isUpdated
                ? '智能界面有更新'
                : widget.isEnabled
                    ? '打开 WebView'
                    : '打开 WebView';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse =
            widget.isUpdated ? 0.78 + (_controller.value * 0.18) : 0.0;
        final glowOpacity = isHighlighted ? pulse : 0.0;
        final tooltipBackground = Color.alphaBlend(
          highlightColor.withValues(alpha: widget.isUpdated ? 0.14 : 0.08),
          colorScheme.surfaceContainerHighest,
        );
        final tooltipTextColor = colorScheme.onSurface;
        final tooltipBorderColor = isHighlighted
            ? highlightColor.withValues(
                alpha: widget.isUpdated ? 0.34 : 0.22,
              )
            : colorScheme.outlineVariant.withValues(alpha: 0.18);
        final iconColor = widget.isOpen
            ? colorScheme.onSurface
            : widget.isUpdated
                ? updatedStyle.accent
                : widget.isEnabled
                    ? enabledStyle.accent
                    : disabledStyle.accent;
        final iconData = widget.isOpen
            ? Icons.arrow_back
            : widget.isEnabled || widget.isUpdated
                ? Icons.open_in_browser_rounded
                : Icons.web_asset_off_outlined;
        final showUpdateLabel = isHighlighted;
        final borderColor = widget.isUpdated
            ? highlightColor.withValues(alpha: stateStyle.borderOpacity)
            : widget.isEnabled
                ? enabledStyle.accent.withValues(alpha: 0.24)
                : isUnavailable
                    ? disabledStyle.accent.withValues(alpha: 0.16)
                    : Colors.transparent;

        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 180),
          showDuration: const Duration(seconds: 2),
          preferBelow: false,
          verticalOffset: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            color: tooltipTextColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          decoration: BoxDecoration(
            color: tooltipBackground.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tooltipBorderColor),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (isHighlighted)
                Container(
                  width: widget.isUpdated ? 42 : 38,
                  height: widget.isUpdated ? 42 : 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: highlightColor.withValues(
                          alpha: glowOpacity * (widget.isUpdated ? 0.22 : 0.14),
                        ),
                        blurRadius: widget.isUpdated ? 14 : 10,
                        spreadRadius: widget.isUpdated ? 2 : 1,
                      ),
                    ],
                  ),
                ),
              Material(
                color: baseBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: borderColor,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onPressed,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: showUpdateLabel ? 12 : 10,
                      vertical: 10,
                    ),
                    child: widget.isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(highlightColor),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                iconData,
                                size: 20,
                                color: iconColor,
                              ),
                              if (showUpdateLabel) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: highlightColor.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: highlightColor.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '有更新',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: highlightColor,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              if (!widget.isOpen && widget.isUpdated)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: highlightColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.surface,
                        width: 1.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: highlightColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: updatedStyle.dotCore,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _WebEntryVisualStyle _resolveEnabledStyle(ColorScheme colorScheme) {
    return _WebEntryVisualStyle(
      accent: colorScheme.primary.withValues(alpha: 0.9),
      background: colorScheme.primaryContainer.withValues(alpha: 0.16),
      borderOpacity: 0.34,
      dotCore: colorScheme.onPrimaryContainer.withValues(alpha: 0.88),
    );
  }

  _WebEntryVisualStyle _resolveDisabledStyle(ColorScheme colorScheme) {
    return _WebEntryVisualStyle(
      accent: colorScheme.onSurfaceVariant.withValues(alpha: 0.44),
      background: colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
      borderOpacity: 0.16,
      dotCore: colorScheme.onSurfaceVariant.withValues(alpha: 0.44),
    );
  }

  _WebEntryVisualStyle _resolveUpdatedStyle(
    ColorScheme colorScheme,
    _WebEntryVisualStyle enabledStyle,
  ) {
    final accent = colorScheme.tertiary;
    final isTooClose = _colorDistance(accent, enabledStyle.accent) < 72;
    if (!isTooClose) {
      return _WebEntryVisualStyle(
        accent: accent,
        background: colorScheme.tertiaryContainer.withValues(alpha: 0.28),
        borderOpacity: 0.72,
        dotCore: colorScheme.onTertiaryContainer,
      );
    }

    final fallbackAccent = Color.alphaBlend(
      colorScheme.inversePrimary.withValues(alpha: 0.72),
      colorScheme.primary,
    );
    final fallbackBackground = Color.alphaBlend(
      colorScheme.secondaryContainer.withValues(alpha: 0.85),
      colorScheme.surfaceContainerHighest,
    );
    return _WebEntryVisualStyle(
      accent: fallbackAccent,
      background: fallbackBackground.withValues(alpha: 0.34),
      borderOpacity: 0.86,
      dotCore: colorScheme.onSecondaryContainer,
    );
  }

  double _colorDistance(Color a, Color b) {
    final dr = (a.r - b.r).abs();
    final dg = (a.g - b.g).abs();
    final db = (a.b - b.b).abs();
    return dr + dg + db;
  }
}

class _WebEntryVisualStyle {
  final Color accent;
  final Color background;
  final double borderOpacity;
  final Color dotCore;

  const _WebEntryVisualStyle({
    required this.accent,
    required this.background,
    required this.borderOpacity,
    required this.dotCore,
  });
}

/// AI 内容免责声明
/// 只要聊天中有员工就显示
class _AiContentDisclaimer extends StatefulWidget {
  final Room room;

  const _AiContentDisclaimer({required this.room});

  @override
  State<_AiContentDisclaimer> createState() => _AiContentDisclaimerState();
}

class _AiContentDisclaimerState extends State<_AiContentDisclaimer> {
  /// 员工信息（如果对方是员工）
  Agent? _employee;

  /// Agent 仓库
  final AgentRepository _repository = AgentRepository();

  @override
  void initState() {
    super.initState();
    _initEmployeeStatus();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  /// 初始化员工状态
  void _initEmployeeStatus() {
    final directChatMatrixID = widget.room.directChatMatrixID;

    if (directChatMatrixID == null) return;

    // 从缓存中快速查找（用于立即显示）
    final cachedEmployee = AgentService.instance.getAgentByMatrixUserId(
      directChatMatrixID,
    );
    if (cachedEmployee != null) {
      setState(() => _employee = cachedEmployee);
    } else {
      // 缓存没有，直接调用 API 获取
      _fetchAndCheckEmployee(directChatMatrixID);
    }
  }

  /// 获取并检查是否是员工
  Future<void> _fetchAndCheckEmployee(String matrixUserId) async {
    try {
      final page = await _repository.getUserAgents(limit: 50);
      final agent = page.agents
          .where((a) => a.matrixUserId == matrixUserId)
          .firstOrNull;
      if (mounted && agent != null) {
        setState(() => _employee = agent);
      }
    } catch (_) {
      // 出错时不显示
    }
  }

  @override
  Widget build(BuildContext context) {
    // 没有员工，不显示
    if (_employee == null) {
      return const SizedBox.shrink();
    }

    // 有员工，显示 AI 提示
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        L10n.of(context).aiContentDisclaimer,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
