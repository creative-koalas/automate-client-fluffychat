import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';

/// 试用期倒计时横幅
/// 显示剩余时间，支持实时倒计时更新
class TrialCountdownBanner extends StatefulWidget {
  /// 试用期到期时间（ISO 8601 格式）
  final String expiresAt;

  /// 过期后的回调
  final VoidCallback? onExpired;

  const TrialCountdownBanner({
    super.key,
    required this.expiresAt,
    this.onExpired,
  });

  @override
  State<TrialCountdownBanner> createState() => _TrialCountdownBannerState();
}

class _TrialCountdownBannerState extends State<TrialCountdownBanner> {
  Timer? _timer;
  Timer? _refreshTimer;
  Duration _remaining = Duration.zero;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(TrialCountdownBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt) {
      _calculateRemaining();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _calculateRemaining() {
    try {
      final expiresAt = DateTime.parse(widget.expiresAt);
      final now = DateTime.now();
      final remaining = expiresAt.difference(now);

      setState(() {
        if (remaining.isNegative) {
          _remaining = Duration.zero;
          _isExpired = true;
        } else {
          _remaining = remaining;
          _isExpired = false;
        }
      });
    } catch (_) {
      setState(() {
        _remaining = Duration.zero;
        _isExpired = true;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // 内部继续计时
      if (_remaining.inSeconds > 0) {
        _remaining = _remaining - const Duration(seconds: 1);
      }

      // 只更新显示（显示最小为1分钟）
      setState(() {});

      // 当真正到期后（剩余时间 <= 0），开始刷新员工列表
      if (_remaining.inSeconds <= 0 && !_isExpired) {
        _isExpired = true;
        // 立即刷新一次
        AgentService.instance.refresh();
        // 每30秒刷新一次，直到组件被销毁（即员工状态已更新）
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          AgentService.instance.refresh();
        });
        widget.onExpired?.call();
      }
    });
  }

  String _formatDuration(L10n l10n) {
    if (_isExpired) {
      return l10n.trialExpired;
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    // 显示最小为1分钟（不显示0分钟）
    final minutes = _remaining.inMinutes % 60;
    final displayMinutes = minutes < 1 ? 1 : minutes;

    if (days > 0) {
      return l10n.trialRemainingDays(days, hours, minutes);
    } else if (hours > 0) {
      return l10n.trialRemainingHours(hours, minutes);
    } else {
      return l10n.trialRemainingMinutes(displayMinutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    // 根据剩余时间决定颜色
    Color backgroundColor;
    Color textColor;
    Color iconColor;

    if (_isExpired || _remaining.inHours < 1) {
      // 已过期或不足1小时，红色警告
      backgroundColor = theme.colorScheme.errorContainer;
      textColor = theme.colorScheme.onErrorContainer;
      iconColor = theme.colorScheme.error;
    } else {
      // 正常状态，蓝色
      backgroundColor = theme.colorScheme.primaryContainer;
      textColor = theme.colorScheme.onPrimaryContainer;
      iconColor = theme.colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isExpired ? Icons.timer_off : Icons.timer_outlined,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.trialPeriod,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(l10n),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.trialHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
