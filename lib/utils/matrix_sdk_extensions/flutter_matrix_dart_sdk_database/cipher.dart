import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/client_manager.dart';
import 'package:psygo/utils/platform_infos.dart';

const _passwordStorageKey = 'database_password';

Future<String?> getDatabaseCipher() async {
  // iOS 和桌面端禁用加密（iOS 的 FlutterSecureStorage 有冷启动挂起问题）
  // Android 启用加密（sqlcipher_flutter_libs 会捆绑原生库）
  if (PlatformInfos.isIOS || PlatformInfos.isDesktop) {
    return null;
  }

  // Android: 使用加密
  String? password;
  try {
    const secureStorage = FlutterSecureStorage();
    final containsEncryptionKey =
        await secureStorage.read(key: _passwordStorageKey) != null;
    if (!containsEncryptionKey) {
      final rng = Random.secure();
      final list = Uint8List(32);
      list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
      final newPassword = base64UrlEncode(list);
      await secureStorage.write(
        key: _passwordStorageKey,
        value: newPassword,
      );
    }
    password = await secureStorage.read(key: _passwordStorageKey);
    if (password == null) throw MissingPluginException();
  } on MissingPluginException catch (e) {
    const FlutterSecureStorage()
        .delete(key: _passwordStorageKey)
        .catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    _sendNoEncryptionWarning(e);
  } catch (e, s) {
    const FlutterSecureStorage()
        .delete(key: _passwordStorageKey)
        .catchError((_) {});
    Logs().w('Unable to init database encryption', e, s);
    _sendNoEncryptionWarning(e);
  }

  return password;
}

void _sendNoEncryptionWarning(Object exception) async {
  final isStored = AppSettings.noEncryptionWarningShown.value;

  if (isStored == true) return;

  final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
  ClientManager.sendInitNotification(
    l10n.noDatabaseEncryption,
    exception.toString(),
  );

  await AppSettings.noEncryptionWarningShown.setItem(true);
}
