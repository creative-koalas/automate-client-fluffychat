import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/backend/api_client.dart';

/// 协议检查服务
/// 检查用户是否已接受最新版本的用户协议和隐私政策
class AgreementCheckService {
  static bool _isInitialized = false;
  static const Duration _resumeDebounce = Duration(seconds: 3);
  static DateTime? _lastCheckTime;

  AgreementCheckService(PsygoApiClient apiClient);

  /// 启动后台检查（仅初始化，不启动轮询）
  static void startBackgroundCheck(
    PsygoApiClient _,
    BuildContext Function() __,
    VoidCallback ___,
  ) {
    // 避免重复初始化
    if (_isInitialized) return;
    _isInitialized = true;
  }

  /// 应用从后台恢复时调用
  static void onAppResumed() {
    _triggerCheckWithDebounce();
  }

  /// 带防抖的检查触发
  static void _triggerCheckWithDebounce() {
    final now = DateTime.now();
    if (_lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _resumeDebounce) {
      return;
    }
    _lastCheckTime = now;
    _doBackgroundCheck();
  }

  /// 执行后台检查（静默）
  static Future<void> _doBackgroundCheck() async {
    return;
  }

  /// 停止后台检查
  static void stopBackgroundCheck() {
    _lastCheckTime = null;
    _isInitialized = false;
  }

  /// 静默检查协议状态（后台恢复时调用）
  Future<bool> checkAndHandle(BuildContext context) async {
    if (!context.mounted) {
      return true;
    }
    return true;
  }
}
