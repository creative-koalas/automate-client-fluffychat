import 'dart:convert';
import 'dart:io';

import 'package:aliyun_push/aliyun_push.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:automate/automate/core/config.dart';

/// 阿里云移动推送服务
///
/// 负责初始化阿里云推送 SDK，处理推送消息回调
class AliyunPushService {
  static AliyunPushService? _instance;
  static AliyunPushService get instance => _instance ??= AliyunPushService._();

  final AliyunPush _aliyunPush = AliyunPush();

  bool _initialized = false;
  String? _deviceId;

  AliyunPushService._();

  /// 阿里云推送配置
  /// Android: appKey=335631945, appSecret=5972362998844c5c8cdb8b0d38e16969
  /// iOS: appKey=335631946, appSecret=91669fd16fb6431a87d70314226a62b6
  static const _androidAppKey = '335631945';
  static const _androidAppSecret = '5972362998844c5c8cdb8b0d38e16969';
  static const _iosAppKey = '335631946';
  static const _iosAppSecret = '91669fd16fb6431a87d70314226a62b6';

  /// 获取当前平台的 appKey
  String get _appKey => Platform.isIOS ? _iosAppKey : _androidAppKey;

  /// 获取当前平台的 appSecret
  String get _appSecret => Platform.isIOS ? _iosAppSecret : _androidAppSecret;

  /// 获取设备 ID（推送 token）
  String? get deviceId => _deviceId;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 初始化阿里云推送
  ///
  /// 应在 app 启动时调用，仅在移动端有效
  Future<bool> initialize() async {
    if (_initialized) {
      Logs().d('[AliyunPush] Already initialized');
      return true;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      Logs().d('[AliyunPush] Not a mobile platform, skipping');
      return false;
    }

    try {
      Logs().i('[AliyunPush] Initializing with appKey: $_appKey');

      // 设置消息回调（必须在初始化之前设置）
      _setupCallbacks();

      // 初始化 SDK
      final result = await _aliyunPush.initPush(
        appKey: _appKey,
        appSecret: _appSecret,
      );

      final code = result['code'] as String?;
      final errorMsg = result['errorMsg'] as String?;

      if (code == kAliyunPushSuccessCode) {
        Logs().i('[AliyunPush] SDK initialized successfully');
        _initialized = true;

        // 获取设备 ID
        await _fetchDeviceId();

        // 设置日志级别（调试时可开启）
        if (kDebugMode) {
          await _aliyunPush.setLogLevel(AliyunPushLogLevel.debug);
        }

        return true;
      } else {
        Logs().e('[AliyunPush] SDK init failed: code=$code, msg=$errorMsg');
        return false;
      }
    } catch (e, s) {
      Logs().e('[AliyunPush] SDK init exception', e, s);
      return false;
    }
  }

  /// 获取设备 ID
  Future<void> _fetchDeviceId() async {
    try {
      _deviceId = await _aliyunPush.getDeviceId();
      Logs().i('[AliyunPush] Device ID: $_deviceId');
    } catch (e) {
      Logs().w('[AliyunPush] Failed to get device ID', e);
    }
  }

  /// 设置消息回调
  void _setupCallbacks() {
    _aliyunPush.addMessageReceiver(
      onNotification: (message) async {
        Logs().i('[AliyunPush] Notification received: $message');
        _handleNotification(message);
      },
      onNotificationOpened: (message) async {
        Logs().i('[AliyunPush] Notification opened: $message');
        _handleNotificationOpened(message);
      },
      onNotificationRemoved: (message) async {
        Logs().d('[AliyunPush] Notification removed: $message');
      },
      onMessage: (message) async {
        Logs().i('[AliyunPush] In-app message received: $message');
        _handleMessage(message);
      },
      onAndroidNotificationReceivedInApp: (message) async {
        Logs().d('[AliyunPush] Android notification in app: $message');
      },
      onIOSChannelOpened: (message) async {
        Logs().d('[AliyunPush] iOS channel opened: $message');
      },
    );

    Logs().d('[AliyunPush] Callbacks registered');
  }

  /// 处理通知消息
  void _handleNotification(Map<dynamic, dynamic> message) {
    // TODO: 在这里处理通知消息
    // 可以触发本地通知或更新 UI
    if (kDebugMode) {
      print('[AliyunPush] Notification: $message');
    }
  }

  /// 处理通知点击
  void _handleNotificationOpened(Map<dynamic, dynamic> message) {
    // TODO: 在这里处理通知点击事件
    // 可以导航到对应的聊天室
    if (kDebugMode) {
      print('[AliyunPush] Notification opened: $message');
    }
  }

  /// 处理应用内消息
  void _handleMessage(Map<dynamic, dynamic> message) {
    // TODO: 在这里处理应用内消息
    // 透传消息，app 在前台时收到
    if (kDebugMode) {
      print('[AliyunPush] Message: $message');
    }
  }

  /// 绑定账号（可选，用于精准推送）
  Future<bool> bindAccount(String account) async {
    if (!_initialized) {
      Logs().w('[AliyunPush] Not initialized, cannot bind account');
      return false;
    }

    try {
      final result = await _aliyunPush.bindAccount(account);
      final code = result['code'] as String?;
      if (code == kAliyunPushSuccessCode) {
        Logs().i('[AliyunPush] Account bound: $account');
        return true;
      } else {
        Logs().w('[AliyunPush] Bind account failed: $result');
        return false;
      }
    } catch (e) {
      Logs().e('[AliyunPush] Bind account exception', e);
      return false;
    }
  }

  /// 解绑账号
  Future<bool> unbindAccount() async {
    if (!_initialized) return false;

    try {
      final result = await _aliyunPush.unbindAccount();
      final code = result['code'] as String?;
      return code == kAliyunPushSuccessCode;
    } catch (e) {
      Logs().e('[AliyunPush] Unbind account exception', e);
      return false;
    }
  }

  /// 绑定标签（可选，用于分组推送）
  Future<bool> bindTag(List<String> tags) async {
    if (!_initialized) return false;

    try {
      final result = await _aliyunPush.bindTag(
        tags,
        target: kAliyunTargetDevice,
      );
      final code = result['code'] as String?;
      if (code == kAliyunPushSuccessCode) {
        Logs().i('[AliyunPush] Tags bound: $tags');
        return true;
      }
      return false;
    } catch (e) {
      Logs().e('[AliyunPush] Bind tag exception', e);
      return false;
    }
  }

  /// 设置角标数量
  Future<void> setBadgeNumber(int count) async {
    if (!_initialized) return;

    try {
      if (Platform.isIOS) {
        await _aliyunPush.setIOSBadgeNum(count);
      } else if (Platform.isAndroid) {
        await _aliyunPush.setAndroidBadgeNum(count);
      }
    } catch (e) {
      Logs().w('[AliyunPush] Set badge failed', e);
    }
  }

  /// 初始化厂商通道（Android 专用，后续接入时使用）
  Future<bool> initThirdPush() async {
    if (!Platform.isAndroid || !_initialized) return false;

    try {
      final result = await _aliyunPush.initAndroidThirdPush();
      final code = result['code'] as String?;
      if (code == kAliyunPushSuccessCode) {
        Logs().i('[AliyunPush] Third push initialized');
        return true;
      }
      Logs().w('[AliyunPush] Third push init failed: $result');
      return false;
    } catch (e) {
      Logs().e('[AliyunPush] Third push init exception', e);
      return false;
    }
  }

  // ============================================================
  // Push Gateway 集成
  // ============================================================

  /// Push Gateway URL（Synapse 调用，用集群内部地址）
  static String get _pushGatewayUrl => '${AutomateConfig.internalBaseUrl}/_matrix/push/v1/notify';

  /// 应用 ID（用于区分 iOS/Android）
  static const String _androidAppId = 'com.creativekoalas.automate.android';
  static const String _iosAppId = 'com.creativekoalas.automate.ios';

  /// 获取当前平台的应用 ID
  String get _appId => Platform.isIOS ? _iosAppId : _androidAppId;

  /// 获取当前平台名称
  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// 生成 pushkey
  /// 格式：{platform}_{deviceId}
  /// 同一设备的 pushkey 保持不变，避免重复注册
  String _generatePushKey() {
    return '${_platform}_${_deviceId ?? 'unknown'}';
  }

  /// 注册推送到 automate-assistant 后端
  ///
  /// [matrixUserID] Matrix 用户 ID（如 @username:localhost）
  /// 返回生成的 pushkey，用于后续注册到 Matrix Synapse
  Future<String?> registerPusherToBackend(String matrixUserID) async {
    if (!_initialized || _deviceId == null) {
      Logs().w('[AliyunPush] Not initialized or no device ID');
      return null;
    }

    final pushKey = _generatePushKey();

    try {
      final uri = Uri.parse('${AutomateConfig.baseUrl}/api/push/register');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'matrix_user_id': matrixUserID,
          'device_id': _deviceId,
          'push_key': pushKey,
          'app_id': _appId,
          'platform': _platform,
          'device_name': Platform.localHostname,
        }),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        Logs().i('[AliyunPush] Pusher registered to backend: pushKey=$pushKey');
        return pushKey;
      } else {
        Logs().e('[AliyunPush] Register pusher failed: ${json['error']}');
        return null;
      }
    } catch (e, s) {
      Logs().e('[AliyunPush] Register pusher exception', e, s);
      return null;
    }
  }

  /// 注册 pusher 到 Matrix Synapse
  ///
  /// 这会告诉 Synapse 当有新消息时通知我们的 Push Gateway
  /// [client] Matrix SDK Client 实例
  /// [pushKey] 从 registerPusherToBackend 返回的 pushkey
  ///
  /// 设计原则（清理旧 pusher）：
  /// 在注册新 pusher 前，先删除同一 app_id 的所有旧 pusher。
  /// 这解决了 device_id 变化导致的重复推送问题。
  /// Matrix 的 append=false 只删除相同 pushkey 的 pusher，无法清理 app_id 相同但 pushkey 不同的旧记录。
  Future<bool> registerPusherToSynapse(Client client, String pushKey) async {
    try {
      // Step 1: 获取当前所有 pusher
      final existingPushers = await client.getPushers();

      // Step 2: 删除同一 app_id 的旧 pusher
      for (final pusher in existingPushers ?? []) {
        if (pusher.appId == _appId && pusher.pushkey != pushKey) {
          Logs().i('[AliyunPush] Removing old pusher: pushKey=${pusher.pushkey}');
          try {
            // 使用 deletePusher 删除（内部设置 kind=null）
            await client.deletePusher(pusher);
            Logs().i('[AliyunPush] Old pusher removed: pushKey=${pusher.pushkey}');
          } catch (e) {
            Logs().w('[AliyunPush] Failed to remove old pusher: ${pusher.pushkey}', e);
            // 继续删除其他的，不中断流程
          }
        }
      }

      // Step 3: 注册新 pusher
      // Matrix Pusher 规范：
      // https://spec.matrix.org/v1.6/client-server-api/#post_matrixclientv3pushersset
      await client.postPusher(
        Pusher(
          pushkey: pushKey,
          kind: 'http',
          appId: _appId,
          appDisplayName: 'Automate',
          deviceDisplayName: Platform.localHostname,
          lang: 'zh-CN',
          data: PusherData(
            url: Uri.parse(_pushGatewayUrl),
            format: 'event_id_only',
          ),
        ),
        append: false,
      );

      Logs().i('[AliyunPush] Pusher registered to Synapse: pushKey=$pushKey');
      return true;
    } catch (e, s) {
      Logs().e('[AliyunPush] Register pusher to Synapse failed', e, s);
      return false;
    }
  }

  /// 完整的推送注册流程
  ///
  /// 1. 注册设备到 automate-assistant 后端
  /// 2. 注册 pusher 到 Matrix Synapse
  /// [client] Matrix SDK Client 实例
  Future<bool> registerPush(Client client) async {
    if (!_initialized || _deviceId == null) {
      Logs().w('[AliyunPush] Not initialized or no device ID');
      return false;
    }

    final matrixUserID = client.userID;
    if (matrixUserID == null) {
      Logs().w('[AliyunPush] User not logged in');
      return false;
    }

    // Step 1: 注册到后端
    final pushKey = await registerPusherToBackend(matrixUserID);
    if (pushKey == null) {
      return false;
    }

    // Step 2: 注册到 Synapse
    return await registerPusherToSynapse(client, pushKey);
  }

  /// 注销推送
  ///
  /// [pushKey] 之前注册时返回的 pushkey
  Future<bool> unregisterPush(String pushKey) async {
    try {
      final uri = Uri.parse('${AutomateConfig.baseUrl}/api/push/unregister')
          .replace(queryParameters: {'push_key': pushKey});

      final response = await http.delete(uri);

      if (response.statusCode == 200) {
        Logs().i('[AliyunPush] Pusher unregistered: pushKey=$pushKey');
        return true;
      } else {
        Logs().w('[AliyunPush] Unregister pusher failed');
        return false;
      }
    } catch (e) {
      Logs().e('[AliyunPush] Unregister pusher exception', e);
      return false;
    }
  }
}
