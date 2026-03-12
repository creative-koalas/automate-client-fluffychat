import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:psygo/utils/platform_infos.dart';

abstract class InstallStateGuard {
  static const _installMarkerKey = 'com.psygo.install.marker.v1';
  static const _clientNamespaceKey = 'com.psygo.store.clients';

  /// iOS 上，Keychain 数据在卸载后可能保留。
  /// 首次安装启动时清理一次 SecureStorage，避免恢复旧会话脏数据。
  static Future<void> clearSecureStorageOnFirstInstall(
    SharedPreferences store,
  ) async {
    if (!PlatformInfos.isIOS) return;

    final isInitialized = store.getBool(_installMarkerKey) ?? false;
    if (isInitialized) return;

    // Avoid logging out existing users on first rollout of this logic.
    // If local client state exists, this is very likely an app upgrade, not reinstall.
    final hasLocalClientState =
        (store.getStringList(_clientNamespaceKey) ?? []).isNotEmpty;
    if (hasLocalClientState) {
      await store.setBool(_installMarkerKey, true);
      debugPrint(
        '[InstallStateGuard] Existing install detected on iOS, skip secure storage clear',
      );
      return;
    }

    try {
      await const FlutterSecureStorage().deleteAll();
      debugPrint(
        '[InstallStateGuard] First install detected on iOS, secure storage cleared',
      );
    } catch (e) {
      debugPrint(
        '[InstallStateGuard] Failed to clear secure storage on first install: $e',
      );
    } finally {
      await store.setBool(_installMarkerKey, true);
    }
  }
}
