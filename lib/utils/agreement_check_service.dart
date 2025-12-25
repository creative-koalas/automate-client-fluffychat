import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:psygo/backend/api_client.dart';

/// 协议检查服务
/// 检查用户是否已接受最新版本的用户协议和隐私政策
class AgreementCheckService {
  final PsygoApiClient _apiClient;

  // 后台定时检查
  static Timer? _backgroundTimer;
  static bool _isDialogShowing = false;
  static const Duration _checkInterval = Duration(minutes: 10);
  static const Duration _resumeDebounce = Duration(seconds: 5);

  // 保存引用以便重试
  static PsygoApiClient? _apiClient_;
  static BuildContext Function()? _getContext;
  static VoidCallback? _onForceLogout;

  static DateTime? _lastCheckTime;

  AgreementCheckService(this._apiClient);

  /// 启动后台定时检查
  static void startBackgroundCheck(
    PsygoApiClient apiClient,
    BuildContext Function() getContext,
    VoidCallback onForceLogout,
  ) {
    // 避免重复启动
    if (_backgroundTimer != null) return;

    _apiClient_ = apiClient;
    _getContext = getContext;
    _onForceLogout = onForceLogout;

    // 定时检查（每10分钟）
    _backgroundTimer = Timer.periodic(_checkInterval, (_) async {
      await _doBackgroundCheck();
    });
  }

  /// 应用从后台恢复时调用
  static void onAppResumed() {
    _triggerCheckWithDebounce();
  }

  /// 带防抖的检查触发
  static void _triggerCheckWithDebounce() {
    final now = DateTime.now();
    if (_lastCheckTime != null && now.difference(_lastCheckTime!) < _resumeDebounce) {
      return;
    }
    _lastCheckTime = now;
    _doBackgroundCheck();
  }

  /// 执行后台检查
  static Future<void> _doBackgroundCheck() async {
    if (_isDialogShowing) return;
    if (_apiClient_ == null || _getContext == null) return;

    final context = _getContext!();
    if (!context.mounted) return;

    final service = AgreementCheckService(_apiClient_!);
    await service._silentCheck(context);
  }

  /// 停止后台定时检查
  static void stopBackgroundCheck() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _lastCheckTime = null;
    _apiClient_ = null;
    _getContext = null;
    _onForceLogout = null;
  }

  /// 静默检查协议状态（后台调用）
  Future<void> _silentCheck(BuildContext context) async {
    try {
      final status = await _apiClient.getAgreementStatus();

      if (status.allAccepted) {
        // 用户已接受所有最新协议
        return;
      }

      if (!context.mounted) return;

      // 用户未接受最新协议，显示提示并强制登出
      _showForceLogoutDialog(context);
    } catch (e) {
      debugPrint('[AgreementCheck] Silent check failed: $e');
      // 静默失败，不处理（可能是网络问题）
    }
  }

  /// 检查协议状态
  /// 返回 true 表示用户已接受所有协议，false 表示需要重新同意
  Future<bool> checkAgreementStatus() async {
    try {
      final status = await _apiClient.getAgreementStatus();
      return status.allAccepted;
    } catch (e) {
      debugPrint('[AgreementCheck] Check failed: $e');
      // 检查失败时默认通过，避免误伤用户
      return true;
    }
  }

  /// 检查协议状态并处理
  /// 返回 true 表示可以继续，false 表示需要强制登出
  Future<bool> checkAndHandle(BuildContext context) async {
    try {
      final status = await _apiClient.getAgreementStatus();

      if (status.allAccepted) {
        return true;
      }

      if (!context.mounted) return false;

      // 用户未接受最新协议，显示提示并强制登出
      _showForceLogoutDialog(context);
      return false;
    } catch (e) {
      debugPrint('[AgreementCheck] Check failed: $e');
      // 检查失败时默认通过，避免误伤用户
      return true;
    }
  }

  /// 显示强制登出弹窗
  void _showForceLogoutDialog(BuildContext context) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.policy_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        title: const Text('协议更新'),
        content: const Text(
          '我们更新了用户协议或隐私政策，请重新登录并同意最新协议后继续使用。',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _isDialogShowing = false;
              // 触发强制登出
              _onForceLogout?.call();
            },
            child: const Text('重新登录'),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
  }
}
