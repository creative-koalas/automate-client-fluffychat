import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';

import 'package:psygo/backend/api_client.dart';
import 'package:psygo/config/app_config.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/backend_error_message.dart';
import 'package:psygo/utils/fluffy_share.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/tap_dismiss_snackbar.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';
import 'package:psygo/widgets/matrix.dart';
import 'package:psygo/widgets/qr_code_viewer.dart';

class ShareInviteLinkPage extends StatefulWidget {
  static const String routePath = '/rooms/share-invite-link';

  const ShareInviteLinkPage({super.key});

  @override
  State<ShareInviteLinkPage> createState() => _ShareInviteLinkPageState();
}

class _ShareInviteLinkPageState extends State<ShareInviteLinkPage> {
  Future<ContactInviteCreateResult>? _contactInviteFuture;
  bool _sharing = false;

  Future<ContactInviteCreateResult> _getContactInvite() {
    return _contactInviteFuture ??= _createContactInvite();
  }

  Future<ContactInviteCreateResult> _createContactInvite() async {
    final apiClient = context.read<PsygoApiClient>();
    try {
      return await apiClient.createContactInvite(
        source: 'share_link',
        metadata: {
          'entrypoint': 'share_invite_link_page',
          'client_platform': _clientPlatformLabel(),
        },
      );
    } catch (e) {
      _contactInviteFuture = null;
      rethrow;
    }
  }

  void _resetContactInvite() {
    setState(() {
      _contactInviteFuture = null;
    });
  }

  Future<void> _shareInvite(ContactInviteCreateResult invite) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final client = Matrix.of(context).client;
      final ownProfile = await client.fetchOwnProfile();
      if (!mounted) return;
      await FluffyShare.share(
        FluffyShare.buildInviteLinkText(
          context,
          inviterName: ownProfile.displayName ?? client.userID!,
          inviteUrl: invite.inviteUrl,
        ),
        context,
      );
    } catch (e) {
      if (!mounted) return;
      showTapDismissSnackBar(
        context,
        friendlyBackendErrorMessage(e, L10n.of(context)),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Future<void> _copyInviteLink(String inviteUrl) async {
    await Clipboard.setData(ClipboardData(text: inviteUrl));
    if (!mounted) return;
    showTapDismissSnackBar(context, L10n.of(context).copiedToClipboard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = Matrix.of(context).client.userID ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).inviteContact),
        actions: [
          IconButton(
            onPressed: _resetContactInvite,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: L10n.of(context).tryAgain,
          ),
        ],
      ),
      body: MaxWidthBody(
        innerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: FutureBuilder<ContactInviteCreateResult>(
          future: _getContactInvite(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.link_off_rounded,
                        size: 44,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        friendlyBackendErrorMessage(
                          snapshot.error ?? Exception('Unknown error'),
                          L10n.of(context),
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _resetContactInvite,
                        icon: const Icon(Icons.refresh_outlined),
                        label: Text(L10n.of(context).tryAgain),
                      ),
                    ],
                  ),
                ),
              );
            }

            final invite = snapshot.data!;
            final inviteUrl = invite.inviteUrl;

            return ListView(
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onSecondaryContainer,
                              child: Icon(Icons.adaptive.share_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                L10n.of(context).shareInviteLink,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          inviteUrl,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              onPressed:
                                  _sharing ? null : () => _shareInvite(invite),
                              icon: _sharing
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(Icons.adaptive.share_outlined),
                              label: Text(L10n.of(context).share),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _copyInviteLink(inviteUrl),
                              icon: const Icon(Icons.copy_outlined),
                              label: Text(L10n.of(context).copy),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showQrCodeViewer(
                      context,
                      inviteUrl,
                      displayText: inviteUrl,
                      fileName: 'contact_invite_qr.png',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius,
                                ),
                                border: Border.all(
                                  width: 3,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: PrettyQrView.data(
                                  data: inviteUrl,
                                  decoration: PrettyQrDecoration(
                                    shape: PrettyQrSmoothSymbol(
                                      roundFactor: 1,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            L10n.of(context).shareInviteLink,
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (userId.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      title: Text(L10n.of(context).yourGlobalUserIdIs),
                      subtitle: SelectableText(userId),
                      trailing: IconButton(
                        onPressed: () => _copyInviteLink(userId),
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: L10n.of(context).copy,
                      ),
                    ),
                  ),
                ],
                if (PlatformInfos.isMobile) const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  String _clientPlatformLabel() {
    if (PlatformInfos.isIOS) return 'ios';
    if (PlatformInfos.isAndroid) return 'android';
    if (PlatformInfos.isMacOS) return 'macos';
    if (PlatformInfos.isWindows) return 'windows';
    if (PlatformInfos.isLinux) return 'linux';
    if (PlatformInfos.isWeb) return 'web';
    return 'unknown';
  }
}
