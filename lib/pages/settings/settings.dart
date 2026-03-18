import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:psygo/core/config.dart';
import 'package:provider/provider.dart';
import 'package:psygo/backend/api_client.dart';
import 'package:psygo/backend/auth_state.dart';
import 'package:psygo/core/token_manager.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/profanity_checker.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:psygo/widgets/dicebear_avatar_picker.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/fluffy_chat_app.dart';
import 'package:psygo/widgets/layouts/desktop_layout.dart';
import '../../widgets/matrix.dart';
import '../bootstrap/bootstrap_dialog.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;
  bool _logoutInProgress = false;

  void updateProfile() => setState(() {
        profileUpdated = true;
        profileFuture = null;
        // 清除侧边栏的 profile 缓存，确保头像同步更新
        DesktopLayout.clearUserCache();
      });

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final l10n = L10n.of(context);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
      validator: (input) {
        final trimmed = input.trim();
        if (trimmed.isEmpty) return l10n.nicknameEmpty;
        if (trimmed.length > 10) return l10n.nicknameTooLong;
        if (!RegExp(r'^[\u4e00-\u9fa5a-zA-Z0-9_]+$').hasMatch(trimmed)) {
          return l10n.nicknameInvalidChars;
        }
        if (containsProfanity(trimmed)) return l10n.nameContainsProfanity;
        return null;
      },
    );
    if (input == null) return;
    final trimmed = input.trim();
    final apiClient = context.read<PsygoApiClient>();
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => apiClient.submitNicknameChangeRequest(trimmed),
    );
    if (success.error == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.nicknameChangeSubmitted)),
        );
      }
    }
  }

  void setAvatarAction() async {
    final selectedUrl = await showDialog<String>(
      context: context,
      builder: (context) => _AvatarPickerDialog(),
    );

    if (selectedUrl == null || !mounted) return;

    final avatarUrl = selectedUrl;
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final l10n = L10n.of(context);

    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final response = await http.get(Uri.parse(avatarUrl));
        if (response.statusCode != 200) {
          throw Exception(l10n.avatarDownloadFailed);
        }
        final mxcUri = await client.uploadContent(
          response.bodyBytes,
          filename: 'avatar.png',
        );
        await client.setProfileField(
          client.userID!,
          'avatar_url',
          {'avatar_url': mxcUri.toString()},
        );
      },
    );

    if (success.error == null && mounted) {
      updateProfile();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.avatarUpdated),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void deleteAccountAction() async {
    final l10n = L10n.of(context);
    final confirmKeyword = l10n.settingsDeleteAccountInputKeyword;

    // 第一次确认
    final firstConfirm = await showOkCancelAlertDialog(
      context: context,
      title: l10n.settingsDeleteAccountConfirmTitle,
      message: l10n.settingsDeleteAccountConfirmMessage,
      okLabel: l10n.settingsDeleteAccountContinue,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (firstConfirm != OkCancelResult.ok) return;

    // 第二次确认，输入"注销"
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.settingsDeleteAccountInputTitle,
      message: l10n.settingsDeleteAccountInputMessage(confirmKeyword),
      okLabel: l10n.settingsDeleteAccountInputConfirm,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (input == null || input.trim() != confirmKeyword) {
      if (input != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsDeleteAccountInputInvalid)),
        );
      }
      return;
    }

    final matrix = Matrix.of(context);
    final auth = context.read<PsygoAuthState>();
    final apiClient = context.read<PsygoApiClient>();

    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // 调用后端 API 注销账号（级联删除 Agent、Matrix 账号等）
        await apiClient.deleteAccount();
      },
    );

    final error = success.error;
    if (error != null) {
      debugPrint('[Settings] Delete account failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsDeleteAccountFailed)),
      );
      return;
    }

    try {
      debugPrint('[Settings] Account deletion successful, cleaning up...');

      // 1. 先清理 Matrix 客户端（本地清理，不调用服务端 API，因为账号已删除）
      final clients = List.from(matrix.widget.clients);
      for (final client in clients) {
        try {
          await client.dispose();
          debugPrint('[Settings] Matrix client disposed');
        } catch (e) {
          debugPrint('[Settings] Matrix client cleanup error: $e');
        }
      }
      // 清空客户端列表
      matrix.widget.clients.clear();

      // 2. 清除 Automate 认证状态
      // AuthGate 会监听到状态变化，自动处理：
      // - 切换窗口大小（PC端）
      // - 跳转到登录页
      // - 触发一键登录（移动端）
      // 注意：Matrix 客户端已经被清理，AuthGate 不会重复操作
      await auth.markLoggedOut();

      debugPrint('[Settings] Account deletion cleanup completed');
    } catch (e) {
      debugPrint('[Settings] Account deletion cleanup error: $e');
    }
  }

  void logoutAction() async {
    if (_logoutInProgress) {
      debugPrint(
          '[Settings] Logout already in progress, ignoring duplicate tap');
      return;
    }

    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;
    final dialogWidth = isDesktop ? 400.0 : screenWidth;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // 标题
              Text(
                l10n.settingsLogoutConfirmTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // 提示信息卡片
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9), // 浅绿色背景
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF4CAF50),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.settingsLogoutConfirmHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 按钮
              Row(
                children: [
                  // 取消按钮
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 退出登录按钮
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.logout,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // 只有明确点击"退出登录"按钮才继续
    if (confirmed != true) {
      return;
    }

    if (!mounted) return;
    setState(() => _logoutInProgress = true);

    // 在 context 失效前获取需要的引用
    final auth = context.read<PsygoAuthState>();
    var needsFallback = false;

    try {
      debugPrint('[Settings] Starting logout...');

      // 清除 Automate 认证状态
      // AuthGate 会监听到状态变化，自动处理：
      // - 退出 Matrix 客户端
      // - 清除缓存
      // - 切换窗口大小
      // - 跳转到登录页
      await auth.markLoggedOut().timeout(const Duration(seconds: 8));
      await auth.load();
      if (auth.isLoggedIn) {
        debugPrint(
            '[Settings] Logout did not clear auth state, fallback required');
        needsFallback = true;
      }

      debugPrint('[Settings] Logout completed');
    } catch (e) {
      debugPrint('[Settings] Logout error: $e');
      needsFallback = true;
    }

    if (needsFallback && mounted) {
      await _forceLocalLogoutFallback();
    }

    if (mounted) {
      setState(() => _logoutInProgress = false);
    }
  }

  Future<void> _forceLocalLogoutFallback() async {
    debugPrint('[Settings] Running logout fallback cleanup...');

    final auth = context.read<PsygoAuthState>();

    // 1) 强制清理 token（本地）
    try {
      await TokenManager.instance.clearTokens();
    } catch (e) {
      debugPrint('[Settings] Fallback clear token error: $e');
    }

    // 2) 再次清理认证状态（幂等）
    try {
      await auth.markLoggedOut().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[Settings] Fallback auth clear error: $e');
    }

    // 3) 强制清理 Matrix 客户端本地状态
    try {
      final matrix = Matrix.of(context);
      final clients = List<Client>.from(matrix.widget.clients);
      for (final client in clients) {
        try {
          if (client.isLogged()) {
            await client.logout().timeout(const Duration(seconds: 3));
          }
        } catch (logoutError) {
          debugPrint('[Settings] Fallback matrix logout error: $logoutError');
          try {
            await client.clear().timeout(const Duration(seconds: 3));
          } catch (clearError) {
            debugPrint('[Settings] Fallback matrix clear error: $clearError');
          }
        }
      }
    } catch (e) {
      debugPrint('[Settings] Fallback matrix cleanup error: $e');
    }

    if (!mounted) {
      return;
    }

    // 4) 最后兜底导航，确保用户离开当前页面
    try {
      if (PlatformInfos.isDesktop) {
        await WindowService.switchToLoginWindow();
        PsygoApp.router.go('/login-signup');
      } else {
        PsygoApp.router.go('/');
      }
    } catch (e) {
      debugPrint('[Settings] Fallback navigation error: $e');
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).clientOrNull;
    if (client == null || !client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    final crossSigning =
        await client.encryption?.crossSigning.isCached() ?? false;
    final needsBootstrap =
        await client.encryption?.keyManager.isCached() == false ||
            client.encryption?.crossSigning.enabled == false ||
            crossSigning == false;
    final isUnknownSession = client.isUnknownSession;
    setState(() {
      showChatBackupBanner = needsBootstrap || isUnknownSession;
    });
  }

  bool? crossSigningCached;
  bool? showChatBackupBanner;

  void firstRunBootstrapAction([_]) async {
    if (showChatBackupBanner != true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await BootstrapDialog(
      client: Matrix.of(context).client,
    ).show(context);
    checkBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).clientOrNull;
    final userID = client?.userID;
    if (client != null && userID != null) {
      profileFuture ??= client.getProfileFromUserId(userID);
    }
    return SettingsView(this);
  }
}

class _AvatarPickerDialog extends StatefulWidget {
  @override
  State<_AvatarPickerDialog> createState() => _AvatarPickerDialogState();
}

class _AvatarPickerDialogState extends State<_AvatarPickerDialog> {
  late String _selectedUrl;

  @override
  void initState() {
    super.initState();
    _selectedUrl = _generateRandomAvatarUrl();
  }

  static String _generateRandomAvatarUrl() {
    final random = Random();
    const styles = DiceBearStyle.values;
    final style = styles[random.nextInt(styles.length)];
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final seed =
        List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
    return '${PsygoConfig.dicebearBaseUrl}/${style.apiName}/png?seed=$seed&size=256';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.changeAvatar,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            DiceBearAvatarPicker(
              initialAvatarUrl: _selectedUrl,
              size: 120,
              onAvatarChanged: (url) => _selectedUrl = url,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedUrl),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
