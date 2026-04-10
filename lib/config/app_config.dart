import 'dart:ui';

import '../core/config.dart';

abstract class AppConfig {
  // Const and final configuration values (immutable)
  static const Color primaryColor = Color(0xFF5625BA);
  static const Color primaryColorLight = Color(0xFFCCBDEA);
  static const Color secondaryColor = Color(0xFF41a2bc);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'psygo://chat/';
  static const String schemePrefix = 'matrix:';
  static const String contactInvitePathPrefix = '/invite/';
  static String get contactInviteBaseUrl => _originFromBaseUrl(PsygoConfig.baseUrl);
  static String get contactInviteUniversalLinkPrefix =>
      '$contactInviteBaseUrl$contactInvitePathPrefix';
  static const String contactInviteCustomScheme = 'psygo';
  static const String contactInviteCustomLinkPrefix =
      '$contactInviteCustomScheme://invite/';
  static String get contactInviteDownloadUrl => contactInviteBaseUrl;
  static const String pushNotificationsChannelId = 'psygo_push';
  static const String pushNotificationsAppId = 'com.psygo.app';
  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;

  static const String website = 'https://fluffy.chat';
  static const String enablePushTutorial =
      'https://fluffy.chat/faq/#push_without_google_services';
  static const String encryptionTutorial =
      'https://fluffy.chat/faq/#how_to_use_end_to_end_encryption';
  static const String startChatTutorial =
      'https://fluffy.chat/faq/#how_do_i_find_other_users';
  static const String appId = 'com.psygo.Psygo';
  static const String appOpenUrlScheme = 'psygo';

  static const String sourceCodeUrl =
      'https://github.com/creative-koalas/automate-client-fluffychat';
  static const String supportUrl =
      'https://github.com/creative-koalas/automate-client-fluffychat/issues';
  static const String changelogUrl = 'https://fluffy.chat/en/changelog/';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/krille-chan/fluffychat/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'servers.joinmatrix.org',
    path: 'servers.json',
  );

  static final Uri privacyUrl = Uri(
    scheme: 'https',
    host: 'psygoai.com',
    path: '/legal/privacy-policy.html',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';

  static String _originFromBaseUrl(String rawBaseUrl) {
    final raw = rawBaseUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return raw.replaceFirst(RegExp(r'/+$'), '');
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceFirst(RegExp(r'/+$'), '');
  }
}
