import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:psygo/backend/backend.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/l10n/l10n_branding.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/tap_dismiss_snackbar.dart';
import 'package:psygo/widgets/qr_code_viewer.dart';
import '../widgets/matrix.dart';

abstract class FluffyShare {
  static Future<void> share(
    String text,
    BuildContext context, {
    bool copyOnly = false,
  }) async {
    if (PlatformInfos.isMobile && !copyOnly) {
      final renderObject = context.findRenderObject();
      final overlayRenderObject = Overlay.maybeOf(
        context,
      )?.context.findRenderObject();
      final box = renderObject is RenderBox
          ? renderObject
          : overlayRenderObject is RenderBox
              ? overlayRenderObject
              : null;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    showTapDismissSnackBar(context, L10n.of(context).copiedToClipboard);
    return;
  }

  static Future<void> shareInviteLink(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => const _InviteLinkDialog(),
    );
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

class _InviteLinkDialog extends StatefulWidget {
  const _InviteLinkDialog();

  @override
  State<_InviteLinkDialog> createState() => _InviteLinkDialogState();
}

class _InviteLinkDialogState extends State<_InviteLinkDialog> {
  ContactInviteCreateResult? _invite;
  Object? _error;
  Duration? _remainingValidity;
  Timer? _expiryTimer;
  bool _loading = false;
  bool _refreshing = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInvite());
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInvite({bool silent = false}) async {
    if (_loading || _refreshing) return;
    final preserveCurrentInvite = silent &&
        _invite != null &&
        ((_computeRemainingValidity(_invite!.expiresAt) ?? Duration.zero) >
            Duration.zero);
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      final api = context.read<PsygoApiClient>();
      final invite = await api.createContactInvite(
        source: 'share_link',
        metadata: {
          'entrypoint': 'share_invite_dialog',
          'client_platform': FluffyShare._platformLabel(),
        },
      );
      if (!mounted) return;
      _bindInvite(invite);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        if (!preserveCurrentInvite) {
          _invite = null;
          _remainingValidity = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _bindInvite(ContactInviteCreateResult invite) {
    _expiryTimer?.cancel();
    setState(() {
      _invite = invite;
      _error = null;
      _remainingValidity = _computeRemainingValidity(invite.expiresAt);
    });

    if (invite.expiresAt == null) {
      return;
    }

    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _computeRemainingValidity(invite.expiresAt);
      if (!mounted) return;
      if (remaining == null) return;
      if (remaining <= Duration.zero) {
        _expiryTimer?.cancel();
        unawaited(_loadInvite(silent: true));
        return;
      }
      setState(() {
        _remainingValidity = remaining;
      });
    });
  }

  Duration? _computeRemainingValidity(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatRemainingValidity(Duration? duration) {
    if (duration == null) return '--:--';
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
      showTapDismissSnackBar(context, e.toString());
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
    final invite = _invite;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(L10n.of(context).shareInviteLink)),
          if (_refreshing)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _loading && invite == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              )
            : invite == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        _error?.toString() ?? 'Unknown error',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _loadInvite(),
                        icon: const Icon(Icons.refresh_outlined),
                        label: Text(L10n.of(context).tryAgain),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: InkWell(
                          onTap: () => showQrCodeViewer(
                            context,
                            invite.inviteUrl,
                            displayText: invite.inviteUrl,
                            fileName: 'contact_invite_qr.png',
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                width: 3,
                                color: theme.colorScheme.primary,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: PrettyQrView.data(
                                data: invite.inviteUrl,
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
                      ),
                      if (_remainingValidity != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formatRemainingValidity(_remainingValidity),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SelectableText(
                        invite.inviteUrl,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          _error.toString(),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
        TextButton.icon(
          onPressed: () => _loadInvite(),
          icon: const Icon(Icons.refresh_outlined),
          label: Text(L10n.of(context).tryAgain),
        ),
        if (invite != null) ...[
          TextButton.icon(
            onPressed: () => _copyInviteLink(invite.inviteUrl),
            icon: const Icon(Icons.copy_outlined),
            label: Text(L10n.of(context).copy),
          ),
          FilledButton.icon(
            onPressed: _sharing ? null : () => _shareInvite(invite),
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : Icon(Icons.adaptive.share_outlined),
            label: Text(L10n.of(context).share),
          ),
        ],
      ],
    );
  }
}
