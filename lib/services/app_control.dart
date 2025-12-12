import 'package:flutter/services.dart';

/// 应用控制服务 - 处理退到后台等操作
class AppControlService {
  static const _channel = MethodChannel('com.creativekoalas.psygo/app_control');

  /// 将应用移到后台（回到用户桌面）
  static Future<bool> moveToBackground() async {
    try {
      final result = await _channel.invokeMethod<bool>('moveToBackground');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
