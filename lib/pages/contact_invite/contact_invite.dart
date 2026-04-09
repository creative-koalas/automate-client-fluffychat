import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher_string.dart';

import 'package:psygo/backend/backend.dart';
import 'package:psygo/config/app_config.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/contact_invite_link.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/fluffy_chat_app.dart';
import 'package:psygo/widgets/matrix.dart';

class ContactInvitePage extends StatefulWidget {
  final String token;

  const ContactInvitePage({super.key, required this.token});

  @override
  State<ContactInvitePage> createState() => _ContactInvitePageState();
}

class _ContactInvitePageState extends State<ContactInvitePage> {
  ContactInvitePreview? _preview;
  String? _errorMessage;
  bool _loadingPreview = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _errorMessage = null;
    });

    try {
      final api = context.read<PsygoApiClient>();
      final preview = await api.previewContactInvite(widget.token);
      if (!mounted) {
        return;
      }
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingPreview = false);
      }
    }
  }

  Future<void> _handlePrimaryAction() async {
    final auth = context.read<PsygoAuthState>();
    if (PlatformInfos.isWeb && !auth.isLoggedIn) {
      await _openInviteInApp();
      return;
    }
    if (!auth.isLoggedIn) {
      await ContactInviteLink.rememberPendingToken(widget.token);
      PsygoApp.router.go(PlatformInfos.isMobile ? '/' : '/login-signup');
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = context.read<PsygoApiClient>();
      final result = await api.claimContactInvite(widget.token);
      if (!mounted) {
        return;
      }
      if (result.status != 'claimed' || result.inviter == null) {
        setState(() {
          _preview = ContactInvitePreview(
            status: result.status,
            expiresAt: result.expiresAt,
            inviter: result.inviter == null
                ? _preview?.inviter
                : ContactInviteInviterPreview(
                    userId: result.inviter!.userId,
                    displayName: result.inviter!.displayName,
                    avatarUrl: result.inviter!.avatarUrl,
                  ),
          );
        });
        _showSnackBar(_statusMessage(result.status));
        return;
      }

      final matrixUserId = result.inviter!.matrixUserId;
      if (matrixUserId.isEmpty) {
        _showSnackBar(L10n.of(context).userNotFound);
        return;
      }

      final client = Matrix.of(context).client;
      final existingDmRoomId = client.getDirectChatFromUserId(matrixUserId);
      if (existingDmRoomId != null) {
        await _completeInvite(existingDmRoomId, roomReused: true);
        if (!mounted) {
          return;
        }
        context.go('/rooms/$existingDmRoomId');
        return;
      }

      final roomId = await client.startDirectChat(
        matrixUserId,
        enableEncryption: false,
      );
      if (!mounted) {
        return;
      }
      await _completeInvite(roomId, roomReused: false);
      if (!mounted) {
        return;
      }
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _completeInvite(
    String roomId, {
    required bool roomReused,
  }) async {
    final api = context.read<PsygoApiClient>();
    try {
      final result = await api.completeContactInvite(
        widget.token,
        acceptedRoomId: roomId,
        metadata: {
          'completion_source': 'contact_invite_page',
          'room_reused': roomReused ? 'true' : 'false',
        },
      );
      if (result.status == 'completed') {
        return;
      }
      _showSnackBar(_statusMessage(result.status));
    } catch (e) {
      debugPrint('[ContactInvite] Failed to complete invite: $e');
      if (!mounted) {
        return;
      }
      _showSnackBar(
        _localizedCopy(
          zh: '聊天已打开，但邀请状态同步失败。',
          en: 'The chat is ready, but the invite status could not be synced.',
        ),
      );
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openInviteInApp() async {
    final launched = await launchUrlString(
      ContactInviteLink.customSchemeUrlForToken(widget.token),
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) {
      return;
    }
    _showSnackBar(
      _localizedCopy(
        zh: '未检测到已安装的 App，请先下载 PsyGo 后重新打开这个邀请链接。',
        en: 'We could not detect the app. Please install PsyGo first, then reopen this invite link.',
      ),
    );
  }

  Future<void> _openDownloadPage() async {
    final launched = await launchUrlString(
      _downloadUrl,
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _downloadUrl));
    if (!mounted) {
      return;
    }
    _showSnackBar(L10n.of(context).copiedToClipboard);
  }

  String get _downloadUrl {
    final uri = Uri.parse(AppConfig.contactInviteDownloadUrl);
    return uri.replace(
      queryParameters: <String, String>{
        'source': 'contact_invite',
        'platform': _landingPlatform.name,
        'token': widget.token,
      },
    ).toString();
  }

  _InviteLandingPlatform get _landingPlatform {
    if (!PlatformInfos.isWeb) {
      if (PlatformInfos.isIOS) return _InviteLandingPlatform.ios;
      if (PlatformInfos.isAndroid) return _InviteLandingPlatform.android;
      if (PlatformInfos.isMacOS) return _InviteLandingPlatform.macos;
      if (PlatformInfos.isWindows) return _InviteLandingPlatform.windows;
      if (PlatformInfos.isLinux) return _InviteLandingPlatform.linux;
      return _InviteLandingPlatform.unknown;
    }

    final userAgent = html.window.navigator.userAgent.toLowerCase();
    if (userAgent.contains('iphone') ||
        userAgent.contains('ipad') ||
        userAgent.contains('ipod')) {
      return _InviteLandingPlatform.ios;
    }
    if (userAgent.contains('android')) {
      return _InviteLandingPlatform.android;
    }
    if (userAgent.contains('macintosh') || userAgent.contains('mac os x')) {
      return _InviteLandingPlatform.macos;
    }
    if (userAgent.contains('windows')) {
      return _InviteLandingPlatform.windows;
    }
    if (userAgent.contains('linux')) {
      return _InviteLandingPlatform.linux;
    }
    return _InviteLandingPlatform.unknown;
  }

  String get _downloadButtonLabel {
    switch (_landingPlatform) {
      case _InviteLandingPlatform.ios:
        return _localizedCopy(
          zh: '下载 iPhone/iPad 版',
          en: 'Download for iPhone/iPad',
        );
      case _InviteLandingPlatform.android:
        return _localizedCopy(zh: '下载 Android 版', en: 'Download for Android');
      case _InviteLandingPlatform.macos:
        return _localizedCopy(zh: '下载 macOS 版', en: 'Download for macOS');
      case _InviteLandingPlatform.windows:
        return _localizedCopy(zh: '下载 Windows 版', en: 'Download for Windows');
      case _InviteLandingPlatform.linux:
        return _localizedCopy(zh: '下载 Linux 版', en: 'Download for Linux');
      case _InviteLandingPlatform.unknown:
        return _localizedCopy(zh: '下载 PsyGo', en: 'Download PsyGo');
    }
  }

  String get _webLandingHint {
    switch (_landingPlatform) {
      case _InviteLandingPlatform.ios:
      case _InviteLandingPlatform.android:
        return _localizedCopy(
          zh: '如果你已经安装 PsyGo，请点“打开 App”。如果还没安装，请先下载，安装完成后重新打开这个邀请链接。',
          en: 'If PsyGo is already installed, tap “Open App”. Otherwise, install it first and reopen this invite link once setup is complete.',
        );
      case _InviteLandingPlatform.macos:
      case _InviteLandingPlatform.windows:
      case _InviteLandingPlatform.linux:
      case _InviteLandingPlatform.unknown:
        return _localizedCopy(
          zh: '你可以先在桌面端安装 PsyGo，安装完成后再次打开这个邀请链接，或在移动设备上继续。',
          en: 'Install PsyGo on your desktop first, then reopen this invite link, or continue on a mobile device instead.',
        );
    }
  }

  Uri? get _inviterAvatarUri {
    final raw = _preview?.inviter?.avatarUrl.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  String _localizedCopy({required String zh, required String en}) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }

  String _statusMessage(String status) {
    final displayName = _preview?.inviter?.displayName ?? '';
    switch (status) {
      case 'active':
        return _localizedCopy(
          zh: displayName.isEmpty
              ? '你收到了一条新的邀请。确认后会直接打开私聊。'
              : '$displayName 邀请你建立联系，确认后会直接打开私聊。',
          en: displayName.isEmpty
              ? 'You received a new invite. Confirm to open a direct chat.'
              : '$displayName invited you to connect. Confirm to open a direct chat.',
        );
      case 'used':
        return _localizedCopy(
          zh: '该邀请已被使用。如果这是你之前接受的邀请，可以继续尝试打开聊天。',
          en: 'This invite has already been used. If you accepted it earlier, you can still try to open the chat.',
        );
      case 'expired':
        return _localizedCopy(
          zh: '该邀请已过期，请联系对方重新发送。',
          en: 'This invite has expired. Ask the sender to share a new one.',
        );
      case 'revoked':
        return _localizedCopy(
          zh: '该邀请已失效，请联系对方重新发送。',
          en: 'This invite is no longer available. Ask the sender to share a new one.',
        );
      case 'self':
        return _localizedCopy(
          zh: '这是你自己创建的邀请链接，不能用于添加自己。',
          en: 'This invite was created by you, so it cannot be used to add yourself.',
        );
      case 'not_found':
        return _localizedCopy(
          zh: '没有找到这个邀请链接，请确认链接是否完整。',
          en: 'This invite link could not be found. Check whether the link is complete.',
        );
      default:
        return _localizedCopy(
          zh: '暂时无法处理这个邀请，请稍后再试。',
          en: 'This invite cannot be processed right now. Please try again later.',
        );
    }
  }

  bool get _canAct {
    final preview = _preview;
    if (preview == null) {
      return false;
    }
    final isLoggedIn = context.read<PsygoAuthState>().isLoggedIn;
    if (PlatformInfos.isWeb && !isLoggedIn) {
      return preview.status == 'active';
    }
    if (!isLoggedIn) {
      return preview.status == 'active';
    }
    return preview.canAttemptClaim;
  }

  String get _primaryButtonLabel {
    final l10n = L10n.of(context);
    if (PlatformInfos.isWeb && !context.read<PsygoAuthState>().isLoggedIn) {
      return _localizedCopy(zh: '打开 App', en: 'Open App');
    }
    if (!context.read<PsygoAuthState>().isLoggedIn) {
      return l10n.login;
    }
    if (_preview?.status == 'used') {
      return l10n.openChat;
    }
    return l10n.connect;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final displayName = _preview?.inviter?.displayName;
    final isLoggedIn = context.watch<PsygoAuthState>().isLoggedIn;
    final showWebLandingActions = PlatformInfos.isWeb && !isLoggedIn;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invite)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _loadingPreview
                ? const Center(
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Avatar(
                        mxContent: _inviterAvatarUri,
                        name:
                            displayName?.isNotEmpty == true ? displayName : 'P',
                        size: 88,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        displayName?.isNotEmpty == true
                            ? displayName!
                            : 'PsyGo',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage ?? _statusMessage(_preview?.status ?? ''),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (showWebLandingActions) ...[
                        const SizedBox(height: 12),
                        Text(
                          _webLandingHint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_canAct)
                        ElevatedButton(
                          onPressed: _submitting ? null : _handlePrimaryAction,
                          child: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_primaryButtonLabel),
                        ),
                      if (showWebLandingActions &&
                          _preview?.status == 'active') ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openDownloadPage,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(_downloadButtonLabel),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

enum _InviteLandingPlatform {
  ios,
  android,
  macos,
  windows,
  linux,
  unknown,
}
