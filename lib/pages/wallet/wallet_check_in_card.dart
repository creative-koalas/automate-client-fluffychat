import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:psygo/backend/api_client.dart';
import 'package:psygo/l10n/l10n.dart';

class WalletCheckInCard extends StatefulWidget {
  const WalletCheckInCard({
    required this.loading,
    required this.isSubmitting,
    required this.celebrationRewardPoints,
    required this.celebrationToken,
    required this.onCheckIn,
    required this.onRetry,
    this.center,
    this.hasError = false,
    super.key,
  });

  final RewardCenter? center;
  final bool loading;
  final bool isSubmitting;
  final bool hasError;
  final int celebrationRewardPoints;
  final int celebrationToken;
  final VoidCallback onCheckIn;
  final VoidCallback onRetry;

  @override
  State<WalletCheckInCard> createState() => _WalletCheckInCardState();
}

class _WalletCheckInCardState extends State<WalletCheckInCard>
    with SingleTickerProviderStateMixin {
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _lightGreen = Color(0xFFE8F5E9);

  late final AnimationController _celebrationController;
  late final Animation<double> _celebrationOpacity;
  late final Animation<Offset> _celebrationOffset;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _celebrationOpacity = CurvedAnimation(
      parent: _celebrationController,
      curve: const Interval(0, 0.72, curve: Curves.easeOut),
    );
    _celebrationOffset =
        Tween<Offset>(
          begin: const Offset(0, 0.45),
          end: const Offset(0, -0.15),
        ).animate(
          CurvedAnimation(
            parent: _celebrationController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  @override
  void didUpdateWidget(covariant WalletCheckInCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.celebrationToken != oldWidget.celebrationToken &&
        widget.celebrationRewardPoints > 0) {
      _celebrationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final outline = colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.55 : 0.35,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHigh,
            _tint(
              colorScheme.surfaceContainerLow,
              _lightGreen,
              isDark ? 0.1 : 0.26,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: outline, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withValues(alpha: isDark ? 0.1 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _buildContent(context, theme),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    final l10n = L10n.of(context);
    final checkIn = widget.center?.checkIn;

    if (widget.loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, theme, null),
          const SizedBox(height: 18),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _primaryGreen,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.hasError || checkIn == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, theme, null),
          const SizedBox(height: 12),
          Text(
            l10n.walletCheckInUnavailable,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              l10n.walletCheckInRetry,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryGreen,
              side: const BorderSide(color: _primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      );
    }

    final activeDay = checkIn.activeDay.clamp(1, checkIn.cycleDays);
    final progress = checkIn.cycleDays <= 0
        ? 0.0
        : (activeDay / checkIn.cycleDays).clamp(0.0, 1.0);
    final isNarrow = MediaQuery.sizeOf(context).width < 392;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, theme, checkIn),
        const SizedBox(height: 18),
        _buildTimeline(context, theme, checkIn),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
          ),
        ),
        const SizedBox(height: 16),
        if (isNarrow) ...[
          _buildSummaryText(context, theme, checkIn),
          const SizedBox(height: 12),
          _buildActionButton(context, checkIn, fullWidth: true),
        ] else
          Row(
            children: [
              Expanded(child: _buildSummaryText(context, theme, checkIn)),
              const SizedBox(width: 12),
              _buildActionButton(context, checkIn),
            ],
          ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    RewardCheckInView? checkIn,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final activeDay = checkIn?.activeDay ?? 1;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _tint(
              theme.colorScheme.surface,
              _lightGreen,
              isDark ? 0.18 : 0.8,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 16,
                color: _primaryGreen,
              ),
              const SizedBox(width: 4),
              Text(
                L10n.of(context).walletCheckInTitle,
                style: const TextStyle(
                  color: _primaryGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (checkIn != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              L10n.of(
                context,
              ).walletCheckInProgress(activeDay, checkIn.cycleDays),
              style: const TextStyle(
                color: _primaryGreen,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    ThemeData theme,
    RewardCheckInView checkIn,
  ) {
    final localeName = L10n.of(context).localeName;
    final activeDay = checkIn.activeDay.clamp(1, checkIn.cycleDays);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in checkIn.schedule)
          Expanded(
            child: _buildTimelineNode(
              context,
              theme,
              item,
              checkIn,
              activeDay: activeDay,
              localeName: localeName,
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineNode(
    BuildContext context,
    ThemeData theme,
    RewardCheckInDayView item,
    RewardCheckInView checkIn, {
    required int activeDay,
    required String localeName,
  }) {
    final isTodayNode = item.day == activeDay;
    final colorScheme = theme.colorScheme;
    final isCompleted = item.isCompleted;
    final isAvailable = item.isAvailable;

    Color fillColor;
    Color borderColor;
    Color foregroundColor;
    IconData icon;

    if (isCompleted) {
      fillColor = _primaryGreen;
      borderColor = _primaryGreen;
      foregroundColor = Colors.white;
      icon = Icons.check_rounded;
    } else if (isAvailable) {
      fillColor = colorScheme.surface;
      borderColor = _primaryGreen;
      foregroundColor = _primaryGreen;
      icon = Icons.bolt_rounded;
    } else {
      fillColor = colorScheme.surfaceContainerHighest;
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.45);
      foregroundColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.65);
      icon = Icons.radio_button_unchecked_rounded;
    }

    return Column(
      children: [
        SizedBox(
          height: 20,
          child:
              isTodayNode &&
                  widget.celebrationRewardPoints > 0 &&
                  _celebrationController.isAnimating
              ? FadeTransition(
                  opacity: _celebrationOpacity,
                  child: SlideTransition(
                    position: _celebrationOffset,
                    child: Text(
                      '+${widget.celebrationRewardPoints}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _primaryGreen,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Text(
          _dateLabelForDay(item.day, activeDay, localeName),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isTodayNode ? FontWeight.w700 : FontWeight.w500,
            color: isTodayNode
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: isTodayNode ? 34 : 30,
          height: isTodayNode ? 34 : 30,
          decoration: BoxDecoration(
            color: fillColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: isTodayNode ? 2 : 1.5,
            ),
            boxShadow: isTodayNode
                ? [
                    BoxShadow(
                      color: _primaryGreen.withValues(alpha: 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: isTodayNode ? 18 : 16,
            color: foregroundColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '+${item.rewardPoints}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isTodayNode ? FontWeight.w800 : FontWeight.w600,
            color: isTodayNode ? _primaryGreen : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryText(
    BuildContext context,
    ThemeData theme,
    RewardCheckInView checkIn,
  ) {
    final l10n = L10n.of(context);
    final headline = checkIn.checkedInToday
        ? l10n.walletCheckInTodayReward(checkIn.todayRewardPoints)
        : l10n.walletCheckInNextReward(checkIn.nextRewardPoints);

    return Text(
      headline,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    RewardCheckInView checkIn, {
    bool fullWidth = false,
  }) {
    final l10n = L10n.of(context);
    final isDone = checkIn.checkedInToday;

    Widget child;
    if (widget.isSubmitting) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.walletCheckInLoading,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      );
    } else {
      child = Text(
        isDone ? l10n.walletCheckInDone : l10n.walletCheckInButton,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 44,
      child: ElevatedButton(
        onPressed: isDone || widget.isSubmitting ? null : widget.onCheckIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDone
              ? _primaryGreen.withValues(alpha: 0.58)
              : _primaryGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primaryGreen.withValues(alpha: 0.58),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: child,
      ),
    );
  }

  String _dateLabelForDay(int day, int activeDay, String localeName) {
    final baseDate = _dateOnly(DateTime.now());
    final displayDate = baseDate.add(Duration(days: day - activeDay));
    return DateFormat('M/d', localeName).format(displayDate);
  }

  DateTime _dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  Color _tint(Color base, Color tint, double amount) {
    return Color.lerp(base, tint, amount) ?? base;
  }
}
