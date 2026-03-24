import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/utils/platform_infos.dart';

Future<String?> getPreferredDownloadSaveDirectory() async {
  final configuredDirectory = AppSettings.downloadSaveDirectory.value.trim();
  if (configuredDirectory.isNotEmpty &&
      await Directory(configuredDirectory).exists()) {
    return configuredDirectory;
  }

  if (PlatformInfos.isMacOS) {
    final username =
        Platform.environment['USER'] ?? Platform.environment['LOGNAME'];
    if (username != null && username.isNotEmpty) {
      final macosDownloadsDirectory = Directory('/Users/$username/Downloads');
      if (await macosDownloadsDirectory.exists()) {
        return macosDownloadsDirectory.path;
      }
    }
  }

  final systemDownloadDirectory = await getDownloadsDirectory();
  return systemDownloadDirectory?.path;
}
