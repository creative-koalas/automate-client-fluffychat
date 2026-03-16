import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:psygo/backend/api_client.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/new_private_chat/new_private_chat_view.dart';
import 'package:psygo/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:psygo/utils/adaptive_bottom_sheet.dart';
import 'package:psygo/utils/backend_error_message.dart';
import 'package:psygo/utils/fluffy_share.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/tap_dismiss_snackbar.dart';
import 'package:psygo/utils/url_launcher.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';

class NewPrivateChat extends StatefulWidget {
  const NewPrivateChat({super.key});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  void searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    final result =
        await Matrix.of(context).client.searchUserDirectory(searchTerm);
    final profiles = result.results;

    if (searchTerm.isValidMatrixId &&
        searchTerm.sigil == '@' &&
        !profiles.any((profile) => profile.userId == searchTerm)) {
      profiles.add(Profile(userId: searchTerm));
    }

    return profiles;
  }

  void inviteAction() => FluffyShare.shareInviteLink(context);

  void showInvitationCodeAction() async {
    final apiClient = context.read<PsygoApiClient>();
    try {
      final info = await apiClient.getInvitationInfo();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogCtx) {
          final theme = Theme.of(dialogCtx);
          final colorScheme = theme.colorScheme;
          final progress = info.maxInvitees <= 0
              ? 0.0
              : (info.currentInvitees / info.maxInvitees).clamp(0.0, 1.0);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF4CAF50), size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).myInvitationCode,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Color.lerp(colorScheme.surface, const Color(0xFFE8F5E9), 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          info.invitationCode,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          foregroundColor: const Color(0xFF4CAF50),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: info.invitationCode));
                          showTapDismissSnackBar(
                            dialogCtx,
                            L10n.of(context).invitationCodeCopied,
                            duration: const Duration(seconds: 1),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.of(context).invitedProgress(info.currentInvitees, info.maxInvitees),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                  ),
                ),
                if (info.isFull)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      L10n.of(context).invitationQuotaFull,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(L10n.of(context).close, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      showTapDismissSnackBar(
        context,
        friendlyBackendErrorMessage(e, L10n.of(context)),
      );
    }
  }

  void openScannerAction() async {
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 21) {
        showTapDismissSnackBar(
          context,
          L10n.of(context).unsupportedAndroidVersionLong,
        );
        return;
      }
    }
    await showAdaptiveBottomSheet(
      context: context,
      builder: (_) => QrScannerModal(
        onScan: (link) => UrlLauncher(context, link).openMatrixToUrl(),
      ),
    );
  }

  void copyUserId() async {
    await Clipboard.setData(
      ClipboardData(text: Matrix.of(context).client.userID!),
    );
    showTapDismissSnackBar(
      context,
      L10n.of(context).copiedToClipboard,
    );
  }

  void openUserModal(Profile profile) => UserDialog.show(
        context: context,
        profile: profile,
      );

  @override
  void dispose() {
    _searchCoolDown?.cancel();
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
