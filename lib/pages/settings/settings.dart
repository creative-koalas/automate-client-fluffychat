import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:psygo/backend/api_client.dart';
import 'package:psygo/backend/auth_state.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
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

  void updateProfile() => setState(() {
        profileUpdated = true;
        profileFuture = null;
      });

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void logoutAction() async {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
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
                '确定退出登录？',
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
                    Icon(
                      Icons.check_circle_outline,
                      color: const Color(0xFF4CAF50),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '退出后，员工仍会继续工作',
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
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
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

    // 同时退出 Matrix 和 Automate
    final matrix = Matrix.of(context);
    final auth = context.read<PsygoAuthState>();

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        // 1. 退出 Matrix
        await matrix.client.logout();
        // 2. 清除 Automate 认证状态
        await auth.markLoggedOut();
        // 3. PC端：切换回登录小窗口
        if (PlatformInfos.isDesktop) {
          await WindowService.switchToLoginWindow();
        }
      },
    );
  }

  void submitFeedbackAction() async {
    final theme = Theme.of(context);

    // 弹出反馈对话框
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _FeedbackDialog(theme: theme),
    );

    if (result == null) return;

    final content = result['content'] ?? '';
    final category = result['category'] ?? 'other';
    final replyEmail = result['reply_email'];

    if (content.isEmpty) return;

    // 获取设备信息
    String? deviceInfo;
    String? appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      deviceInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {}

    final apiClient = context.read<PsygoApiClient>();
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => apiClient.submitFeedback(
        content: content,
        category: category,
        replyEmail: replyEmail,
        appVersion: appVersion,
        deviceInfo: deviceInfo,
      ),
    );

    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反馈提交成功，感谢您的反馈！')),
      );
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
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
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(
      client.userID!,
    );
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }

/// 反馈对话框
class _FeedbackDialog extends StatefulWidget {
  final ThemeData theme;

  const _FeedbackDialog({required this.theme});

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _contentController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedCategory = 'suggestion';

  final _categories = [
    {'value': 'bug', 'label': 'Bug 反馈', 'icon': Icons.bug_report_outlined},
    {'value': 'suggestion', 'label': '功能建议', 'icon': Icons.lightbulb_outlined},
    {'value': 'complaint', 'label': '问题投诉', 'icon': Icons.report_outlined},
    {'value': 'other', 'label': '其他', 'icon': Icons.more_horiz},
  ];

  @override
  void dispose() {
    _contentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(
                  Icons.feedback_outlined,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '意见反馈',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 反馈类型选择
            Text(
              '反馈类型',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat['value'];
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                      const SizedBox(width: 4),
                      Text(cat['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat['value'] as String);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 反馈内容
            Text(
              '反馈内容',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: '请详细描述您的问题或建议...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 回复邮箱（可选）
            Text(
              '回复邮箱（可选）',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: '方便我们回复您',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 按钮
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_contentController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入反馈内容')),
                        );
                        return;
                      }
                      Navigator.of(context).pop({
                        'content': _contentController.text.trim(),
                        'category': _selectedCategory,
                        'reply_email': _emailController.text.trim(),
                      });
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '提交',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
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
