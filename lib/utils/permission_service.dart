import 'dart:io';

import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限管理服务
///
/// 简洁的权限请求：直接请求系统权限，不弹预授权对话框
class PermissionService {
  static PermissionService? _instance;
  static PermissionService get instance => _instance ??= PermissionService._();

  PermissionService._();

  /// 是否已请求过权限（避免重复请求）
  bool _hasRequestedNotification = false;
  bool _hasRequestedBattery = false;

  /// 请求推送所需的所有权限
  ///
  /// 在登录成功后调用，会按顺序请求：
  /// 1. 通知权限（Android 13+ / iOS）
  /// 2. 电池优化白名单（Android）
  Future<void> requestPushPermissions() async {
    // 请求通知权限
    await requestNotificationPermission();

    // Android 请求电池优化白名单
    if (Platform.isAndroid) {
      await requestBatteryOptimization();
    }
  }

  /// 请求通知权限
  ///
  /// Android 13+ (API 33) 和 iOS 需要运行时请求
  Future<bool> requestNotificationPermission() async {
    if (_hasRequestedNotification) {
      Logs().d('[Permission] Notification permission already requested');
      return await Permission.notification.isGranted;
    }

    // 检查当前状态
    final status = await Permission.notification.status;
    Logs().d('[Permission] Notification status: $status');

    if (status.isGranted) {
      return true;
    }

    // 直接请求权限（不弹预授权对话框）
    _hasRequestedNotification = true;
    final result = await Permission.notification.request();
    Logs().i('[Permission] Notification permission result: $result');

    return result.isGranted;
  }

  /// 请求电池优化白名单（Android 专用）
  ///
  /// 让系统不会杀死后台 App，确保推送能正常接收
  Future<bool> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return true;

    if (_hasRequestedBattery) {
      Logs().d('[Permission] Battery optimization already requested');
      return await Permission.ignoreBatteryOptimizations.isGranted;
    }

    // 检查当前状态
    final status = await Permission.ignoreBatteryOptimizations.status;
    Logs().d('[Permission] Battery optimization status: $status');

    if (status.isGranted) {
      return true;
    }

    // 直接请求权限（不弹预授权对话框）
    _hasRequestedBattery = true;
    final result = await Permission.ignoreBatteryOptimizations.request();
    Logs().i('[Permission] Battery optimization result: $result');

    return result.isGranted;
  }

  /// 检查通知权限状态
  Future<bool> isNotificationGranted() async {
    return await Permission.notification.isGranted;
  }

  /// 检查电池优化状态
  Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// 打开应用设置页面
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// 重置请求状态（用于测试或重新请求）
  void reset() {
    _hasRequestedNotification = false;
    _hasRequestedBattery = false;
  }
}
