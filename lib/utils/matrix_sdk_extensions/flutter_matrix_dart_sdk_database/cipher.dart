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
  // iOS FIX: Disable SQLCipher on iOS only
  // SQLCipher library fails to load in iOS Release mode with error:
  // "Bad state: SQLCipher library is not available"
  // Android continues to use SQLCipher normally for security
  if (PlatformInfos.isIOS) {
    Logs().i('[Cipher] Database encryption disabled on iOS (SQLCipher library issue in Release mode)');
    return null;
  }

  // Android and other platforms: use SQLCipher
  const storage = FlutterSecureStorage();
  try {
    // Try to get existing password from secure storage
    var password = await storage.read(key: _passwordStorageKey);
    if (password == null) {
      // Generate a new password if none exists
      const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
      final random = Random.secure();
      password = String.fromCharCodes(
        Iterable.generate(
          32,
          (_) => chars.codeUnitAt(random.nextInt(chars.length)),
        ),
      );
      await storage.write(key: _passwordStorageKey, value: password);
      Logs().i('Generated new database encryption password');
    }
    return password;
  } catch (e, s) {
    Logs().e('Unable to get database cipher from secure storage', e, s);
    _sendNoEncryptionWarning(e);
    return null;
  }
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
