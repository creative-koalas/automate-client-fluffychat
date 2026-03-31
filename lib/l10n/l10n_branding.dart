import 'package:psygo/core/config.dart';
import 'package:psygo/l10n/l10n.dart';

extension L10nBrandingExtension on L10n {
  String _brand(String text) {
    final tokens = <String>{
      automate,
      title,
      'PsyGo',
      'Psygo',
      PsygoConfig.defaultAppName,
      'FluffyChat',
      'FuffyChat',
      'FluffyChät',
    }.where((token) => token.isNotEmpty);

    var branded = text;
    for (final token in tokens) {
      branded = branded.replaceAll(token, PsygoConfig.appName);
    }
    return branded;
  }

  String brandedInviteText(String username, String link) =>
      _brand(inviteText(username, link));

  String get brandedNewMessage => _brand(newMessageInPsygo);

  String get brandedNoGoogleServicesWarning => _brand(noGoogleServicesWarning);

  String get brandedMaintenanceBlockedMessage =>
      _brand(maintenanceBlockedMessage);

  String get brandedAppIntroduction => _brand(appIntroduction);

  String get brandedScreenSharingDetail => _brand(screenSharingDetail);
}
