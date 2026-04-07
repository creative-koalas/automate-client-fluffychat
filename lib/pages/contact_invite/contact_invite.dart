import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:psygo/backend/backend.dart';
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
    if (!isLoggedIn) {
      return preview.status == 'active';
    }
    return preview.canAttemptClaim;
  }

  String get _primaryButtonLabel {
    final l10n = L10n.of(context);
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
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
