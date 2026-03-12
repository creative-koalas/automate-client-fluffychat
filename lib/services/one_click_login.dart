import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 阿里云一键登录服务（使用官方 SDK）
///
/// 正确流程：
/// 1. initSdk - 初始化 SDK
/// 2. accelerateLogin - 预取号（必须成功后才能唤起授权页）
/// 3. oneClickLogin - 唤起授权页获取 token
class OneClickLoginService {
  static const _channel = MethodChannel('com.creativekoalas.psygo/one_click_login');

  /// 初始化 SDK
  /// [secretKey] 阿里云控制台获取的密钥
  static Future<Map<String, dynamic>> initSdk(String secretKey) async {
    try {
      debugPrint('OneClickLogin: Initializing SDK...');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('initSdk', {
        'secretKey': secretKey,
      }).timeout(const Duration(seconds: 5));
      debugPrint('OneClickLogin: SDK init result: $result');
      return Map<String, dynamic>.from(result ?? {});
    } on TimeoutException {
      debugPrint('OneClickLogin: SDK init timed out');
      return {
        'code': 'TIMEOUT',
        'msg': 'SDK初始化超时',
      };
    } on PlatformException catch (e) {
      debugPrint('OneClickLogin: SDK init failed: ${e.message}');
      return {
        'code': e.code,
        'msg': e.message,
      };
    }
  }

  /// 预取号（加速登录）
  /// 必须在 oneClickLogin 之前调用并成功
  /// [timeout] 超时时间（毫秒），默认 5000ms
  static Future<Map<String, dynamic>> accelerateLogin({int timeout = 5000}) async {
    try {
      debugPrint('OneClickLogin: Starting pre-login (accelerate)...');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('accelerateLogin', {
        'timeout': timeout,
      }).timeout(Duration(milliseconds: timeout + 2000));
      debugPrint('OneClickLogin: Pre-login result: $result');
      return Map<String, dynamic>.from(result ?? {});
    } on TimeoutException {
      debugPrint('OneClickLogin: Pre-login timed out');
      return {
        'code': 'TIMEOUT',
        'msg': '预取号超时',
      };
    } on PlatformException catch (e) {
      debugPrint('OneClickLogin: Pre-login failed: ${e.code} - ${e.message}');
      return {
        'code': e.code,
        'msg': e.message,
      };
    }
  }

  /// 检查环境是否可用（异步，实际结果通过回调返回）
  static Future<Map<String, dynamic>> checkEnvAvailable() async {
    try {
      debugPrint('OneClickLogin: Checking environment...');
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('checkEnvAvailable')
          .timeout(const Duration(seconds: 5));
      debugPrint('OneClickLogin: Environment check result: $result');
      return Map<String, dynamic>.from(result ?? {});
    } on TimeoutException {
      debugPrint('OneClickLogin: Environment check timed out');
      return {
        'code': 'TIMEOUT',
        'msg': '环境检查超时',
      };
    } on PlatformException catch (e) {
      debugPrint('OneClickLogin: Environment check failed: ${e.message}');
      return {
        'code': e.code,
        'msg': e.message,
      };
    }
  }

  /// 执行一键登录（唤起授权页）
  /// [timeout] 超时时间（毫秒），默认 5000ms
  /// 返回包含 token 的 Map，或者错误信息
  static Future<Map<String, dynamic>> oneClickLogin({int timeout = 5000}) async {
    try {
      debugPrint('OneClickLogin: Starting login with timeout: $timeout');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('oneClickLogin', {
        'timeout': timeout,
      });
      debugPrint('OneClickLogin: Login result: $result');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      debugPrint('OneClickLogin: Login failed: ${e.code} - ${e.message}');
      return {
        'code': e.code,
        'msg': e.message,
      };
    }
  }

  /// 关闭授权页
  static Future<bool> quitLoginPage() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('quitLoginPage')
          .timeout(const Duration(seconds: 2));
      return result ?? false;
    } on TimeoutException {
      debugPrint('OneClickLogin: Quit page timed out');
      return false;
    } on PlatformException catch (e) {
      debugPrint('OneClickLogin: Quit page failed: ${e.message}');
      return false;
    }
  }

  /// 完整的一键登录流程
  /// 包含：初始化 SDK → 预取号 → 执行登录
  /// 返回 token 或抛出异常
  static Future<String> performOneClickLogin({
    required String secretKey,
    int timeout = 5000,
  }) async {
    // 1. 初始化 SDK
    debugPrint('OneClickLogin: Step 1 - Initializing SDK...');
    final initResult = await initSdk(secretKey);
    final initCode = initResult['code']?.toString();
    if (initCode != '600000') {
      throw Exception('SDK初始化失败($initCode): ${initResult['msg']}');
    }

    // 1.5 环境检查（可选但有助于定位网络/运营商问题）
    debugPrint('OneClickLogin: Step 1.5 - Checking environment...');
    final envResult = await checkEnvAvailable();
    final envCode = envResult['code']?.toString();
    if (envCode != '600000') {
      throw Exception('环境检查失败($envCode): ${envResult['msg']}');
    }

    // 2. 预取号（关键步骤！）
    debugPrint('OneClickLogin: Step 2 - Pre-login (accelerate)...');
    final accelerateResult = await accelerateLogin(timeout: timeout);
    final accelerateCode = accelerateResult['code']?.toString();
    if (accelerateCode != '600000') {
      throw Exception('预取号失败($accelerateCode): ${accelerateResult['msg']}');
    }
    debugPrint('OneClickLogin: Pre-login success, vendor: ${accelerateResult['vendor']}');

    // 3. 执行登录（唤起授权页）
    debugPrint('OneClickLogin: Step 3 - Performing login (show auth page)...');
    final loginResult = await oneClickLogin(timeout: timeout);

    final code = loginResult['code']?.toString();
    if (code == '600000') {
      final token = loginResult['token'] as String?;
      if (token != null && token.isNotEmpty) {
        debugPrint('OneClickLogin: Got token: ${token.substring(0, 20)}...');
        return token;
      }
      throw Exception('未获取到认证 token');
    }

    // 700001: 用户点击"其他方式登录"按钮，正常行为，抛出特定异常
    if (code == '700001') {
      throw SwitchLoginMethodException();
    }

    throw Exception('一键登录失败($code): ${loginResult['msg']}');
  }
}

/// 用户选择切换到其他登录方式的异常
class SwitchLoginMethodException implements Exception {
  @override
  String toString() => '用户选择其他登录方式';
}
