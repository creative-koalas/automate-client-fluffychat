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
  // 禁用数据库加密，简化部署
  return null;
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
