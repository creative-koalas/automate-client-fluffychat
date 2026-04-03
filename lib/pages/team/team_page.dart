import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:psygo/backend/auth_state.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/core/config.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/models/hire_result.dart';
import 'package:psygo/repositories/agent_repository.dart';
import 'package:psygo/repositories/agent_template_repository.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/services/recruit_guide_service.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/widgets/custom_hire_dialog.dart';
import 'package:psygo/widgets/recruit_entry_guide_highlight.dart';

import 'package:psygo/pages/wallet/wallet_page.dart';
import 'employees_tab.dart' show EmployeesTab, EmployeesTabState;

/// Team main page
/// Simplified team page with the employee list as the main content.
class TeamPage extends StatefulWidget {
  final bool isVisible;

  const TeamPage({
    super.key,
    this.isVisible = true,
  });

  @override
  State<TeamPage> createState() => TeamPageController();
}

class TeamPageController extends State<TeamPage> {
  // GlobalKey to access EmployeesTab state.
  final GlobalKey<EmployeesTabState> _employeesTabKey = GlobalKey();
  bool _showRecruitGuideHighlight = false;
  bool _recruitLimitReached = false;
  static const int _maxRecruitEmployeeCount = 3;
  static const Duration _recruitTapCooldown = Duration(seconds: 2);
  DateTime? _lastRecruitTapAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyEmployeesTabVisibility();
      unawaited(_syncRecruitGuideHighlight());
      unawaited(_syncRecruitLimitState());
    });
  }

  @override
  void didUpdateWidget(covariant TeamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      _notifyEmployeesTabVisibility();
    }
  }

  void _notifyEmployeesTabVisibility() {
    _employeesTabKey.currentState?.onTabVisibilityChanged(widget.isVisible);
  }

  /// Refresh employee list without switching tab
  /// Called after successful hire (background refresh)
  void refreshEmployeeList() {
    _employeesTabKey.currentState?.refreshEmployeeList();
  }

  void refreshEmployeeListSilently() {
    final tabState = _employeesTabKey.currentState;
    if (tabState == null) return;
    unawaited(tabState.refreshEmployeeListSilently());
  }

  void addPendingEmployeeCard({
    required String employeeName,
    required String agentId,
    String? avatarUrl,
  }) {
    _employeesTabKey.currentState?.addPendingEmployee(
      displayName: employeeName,
      agentId: agentId,
      avatarUrl: avatarUrl,
    );
  }

  void removePendingEmployeeCard(String agentId) {
    _employeesTabKey.currentState?.removePendingEmployee(agentId);
  }

  bool get showRecruitGuideHighlight => _showRecruitGuideHighlight;
  bool get recruitLimitReached => _recruitLimitReached;

  void handleRecruitLimitChanged(bool reached) {
    if (!mounted || _recruitLimitReached == reached) {
      return;
    }
    setState(() {
      _recruitLimitReached = reached;
    });
  }

  Future<void> _syncRecruitGuideHighlight() async {
    final shouldShow = await _shouldShowRecruitGuide();
    if (!mounted || _showRecruitGuideHighlight == shouldShow) {
      return;
    }
    setState(() {
      _showRecruitGuideHighlight = shouldShow;
    });
  }

  Future<bool> _shouldShowRecruitGuide() async {
    final userId = context.read<PsygoAuthState>().userId;
    return RecruitGuideService.instance.shouldShowGuide(userId);
  }

  Future<void> _markRecruitGuideCompleted() async {
    final userId = context.read<PsygoAuthState>().userId;
    await RecruitGuideService.instance.markGuideCompleted(userId);
    if (!mounted || !_showRecruitGuideHighlight) return;
    setState(() {
      _showRecruitGuideHighlight = false;
    });
  }

  Future<bool> _hasReachedRecruitLimit() async {
    if (!PsygoConfig.isProdEnvironment) {
      return false;
    }
    final repository = AgentRepository();
    try {
      final page = await repository.getUserAgents(
        limit: _maxRecruitEmployeeCount,
        forceRefresh: true,
      );
      return page.agents.length >= _maxRecruitEmployeeCount || page.hasNextPage;
    } catch (e) {
      debugPrint('[TeamPage] Failed to fetch employee count: $e');
      return AgentService.instance.agents.length >= _maxRecruitEmployeeCount;
    } finally {
      repository.dispose();
    }
  }

  Future<void> _syncRecruitLimitState() async {
    final reached = await _hasReachedRecruitLimit();
    if (!mounted || _recruitLimitReached == reached) {
      return;
    }
    setState(() {
      _recruitLimitReached = reached;
    });
  }

  void _showRecruitLimitSnackBar(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: scaffoldMessenger.hideCurrentSnackBar,
          child: Text(l10n.recruitLimitReachedMessage),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> openRecruitMenu(BuildContext context) async {
    if (_employeesTabKey.currentState?.hasOnboardingEmployees == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).loadingPleaseWait),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final reachedLimit = await _hasReachedRecruitLimit();
    if (!mounted) return;
    if (_recruitLimitReached != reachedLimit) {
      setState(() {
        _recruitLimitReached = reachedLimit;
      });
    }
    if (reachedLimit) {
      final now = DateTime.now();
      final lastTap = _lastRecruitTapAt;
      if (lastTap != null && now.difference(lastTap) < _recruitTapCooldown) {
        return;
      }
      _lastRecruitTapAt = now;
      _showRecruitLimitSnackBar(context);
      return;
    }

    final repository = AgentTemplateRepository();
    final isDesktop = FluffyThemes.isColumnMode(context);
    final showRecruitGuide = await _shouldShowRecruitGuide();
    if (!mounted) {
      repository.dispose();
      return;
    }

    try {
      final result = isDesktop
          ? await showDialog<HireResult>(
              context: context,
              builder: (dialogContext) {
                final dialogWidth =
                    (MediaQuery.sizeOf(dialogContext).width - 48)
                        .clamp(520.0, 580.0)
                        .toDouble();
                return Dialog(
                  backgroundColor: Colors.transparent,
                  child: SizedBox(
                    width: dialogWidth,
                    child: CustomHireDialog(
                      repository: repository,
                      isDialog: true,
                      showRecruitGuide: showRecruitGuide,
                      onRecruitGuideCompleted: _markRecruitGuideCompleted,
                    ),
                  ),
                );
              },
            )
          : await showModalBottomSheet<HireResult>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              isDismissible: true,
              enableDrag: true,
              showDragHandle: false,
              builder: (_) => CustomHireDialog(
                repository: repository,
                showRecruitGuide: showRecruitGuide,
                onRecruitGuideCompleted: _markRecruitGuideCompleted,
              ),
            );

      if (!mounted || result == null) return;

      final displayName = result.displayName.trim();
      final employeeName = displayName.isNotEmpty ? displayName : 'Employee';
      addPendingEmployeeCard(
        employeeName: employeeName,
        agentId: result.agentId,
        avatarUrl: result.avatarUrl,
      );
      refreshEmployeeListSilently();
      unawaited(AgentService.instance.refresh());
      try {
        await result.responseFuture;
      } catch (e) {
        if (!mounted) return;
        removePendingEmployeeCard(result.agentId);
        final message =
            e.toLocalizedString(context, ExceptionContext.hireEmployee);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (!mounted) return;
      refreshEmployeeListSilently();
      unawaited(AgentService.instance.refresh());
    } finally {
      repository.dispose();
      unawaited(_syncRecruitGuideHighlight());
      unawaited(_syncRecruitLimitState());
    }
  }

  @override
  Widget build(BuildContext context) => TeamPageView(this);
}

class TeamPageView extends StatelessWidget {
  final TeamPageController controller;

  const TeamPageView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final recruitButtonDisabled = controller.recruitLimitReached;
    final recruitGuideDescription = controller.showRecruitGuideHighlight
        ? l10n.recruitGuideStepCreateBody
        : l10n.customHireDescription;
    final recruitButtonContentColor = recruitButtonDisabled
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.08),
                theme.colorScheme.surface,
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.05),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              l10n.teamPageTitle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          // Wallet entry hidden by requirement. Keep logic for easy rollback.
          // Container(
          //   margin: const EdgeInsets.only(right: 12),
          //   decoration: BoxDecoration(
          //     color: theme.colorScheme.surfaceContainerHighest
          //         .withValues(alpha: 0.5),
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   child: IconButton(
          //     icon: Icon(
          //       Icons.account_balance_wallet_rounded,
          //       color: theme.colorScheme.primary,
          //       size: 22,
          //     ),
          //     tooltip: l10n.walletTitle,
          //     onPressed: () {
          //       Navigator.of(context).push(
          //         MaterialPageRoute(
          //           builder: (context) => const WalletPage(),
          //         ),
          //       );
          //     },
          //   ),
          // ),
        ],
      ),
      body: EmployeesTab(
        key: controller._employeesTabKey,
        onRecruitLimitChanged: controller.handleRecruitLimitChanged,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: RecruitEntryGuideHighlight(
        visible: controller.showRecruitGuideHighlight,
        title: l10n.customHire,
        description: recruitGuideDescription,
        actionLabel: l10n.customHire,
        onAction: () => unawaited(controller.openRecruitMenu(context)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: recruitButtonDisabled
                  ? [
                      theme.colorScheme.surfaceContainerHigh,
                      theme.colorScheme.surfaceContainerHighest,
                    ]
                  : [
                      theme.colorScheme.primary,
                      theme.colorScheme.tertiary,
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: recruitButtonDisabled
                ? Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.8,
                    ),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: recruitButtonDisabled
                    ? theme.colorScheme.shadow.withValues(alpha: 0.08)
                    : theme.colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => unawaited(controller.openRecruitMenu(context)),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: recruitButtonContentColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.customHire,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: recruitButtonContentColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
