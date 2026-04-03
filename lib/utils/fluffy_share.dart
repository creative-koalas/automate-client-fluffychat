import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:psygo/backend/backend.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/l10n/l10n_branding.dart';
import 'package:psygo/utils/backend_error_message.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/tap_dismiss_snackbar.dart';
import '../widgets/matrix.dart';

abstract class FluffyShare {
  static Future<void> share(
    String text,
    BuildContext context, {
    bool copyOnly = false,
  }) async {
    if (PlatformInfos.isMobile && !copyOnly) {
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    showTapDismissSnackBar(context, L10n.of(context).copiedToClipboard);
    return;
  }

  static Future<void> shareInviteLink(BuildContext context) async {
    try {
      final client = Matrix.of(context).client;
      final api = context.read<PsygoApiClient>();
      final ownProfile = await client.fetchOwnProfile();
      final invite = await api.createContactInvite(
        source: 'share_link',
        metadata: {
          'entrypoint': 'share_invite_link',
          'client_platform': _platformLabel(),
        },
      );
      await FluffyShare.share(
        buildInviteLinkText(
          context,
          inviterName: ownProfile.displayName ?? client.userID!,
          inviteUrl: invite.inviteUrl,
        ),
        context,
      );
    } catch (e) {
      showTapDismissSnackBar(
        context,
        friendlyBackendErrorMessage(e, L10n.of(context)),
      );
    }
  }

  static String buildInviteLinkText(
    BuildContext context, {
    required String inviterName,
    required String inviteUrl,
  }) {
    return L10n.of(context).brandedInviteText(inviterName, inviteUrl);
  }

  static String _platformLabel() {
    if (PlatformInfos.isIOS) return 'ios';
    if (PlatformInfos.isAndroid) return 'android';
    if (PlatformInfos.isMacOS) return 'macos';
    if (PlatformInfos.isWindows) return 'windows';
    if (PlatformInfos.isLinux) return 'linux';
    if (PlatformInfos.isWeb) return 'web';
    return 'unknown';
  }
}
