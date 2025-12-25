import 'package:shared_preferences/shared_preferences.dart';

import 'package:psygo/utils/platform_infos.dart';

abstract class UpdateNotifier {
  static const String versionStoreKey = 'last_known_version';

  static void showUpdateSnackBar() async {
    final currentVersion = await PlatformInfos.getVersion();
    final store = await SharedPreferences.getInstance();
    final storedVersion = store.getString(versionStoreKey);

    if (currentVersion != storedVersion) {
      await store.setString(versionStoreKey, currentVersion);
    }
  }
}
