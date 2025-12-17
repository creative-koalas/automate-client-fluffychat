/// 登录流程公共逻辑 Mixin
/// 一键登录和验证码登录共用：邀请码弹窗、Matrix 登录、登录后跳转
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:psygo/widgets/matrix.dart';
import 'package:psygo/backend/backend.dart';
import 'package:psygo/core/config.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/permission_service.dart';
import 'package:psygo/utils/window_service.dart';

/// 登录流程公共逻辑
/// 使用方式：class MyController extends State<MyWidget> with LoginFlowMixin
mixin LoginFlowMixin<T extends StatefulWidget> on State<T> {
  /// 子类必须提供 backend 实例
  PsygoApiClient get backend;

  /// 子类必须提供设置错误信息的方法
  void setLoginError(String? error);

  /// 子类必须提供设置 loading 状态的方法
  void setLoading(bool loading);

  /// 处理验证后的登录流程（公共逻辑）
  /// [verifyResponse] - 验证手机号返回的结果
  /// [onCancel] - 用户取消邀请码输入时的回调（可选）
  /// 返回 true 表示流程继续，false 表示用户取消或出错
  Future<bool> handlePostVerify({
    required VerifyPhoneResponse verifyResponse,
    VoidCallback? onCancel,
  }) async {
    if (!mounted) return false;

    // 新用户需要输入邀请码
    String? invitationCode;
    if (verifyResponse.isNewUser) {
      invitationCode = await showInvitationCodeDialog(verifyResponse.phone);
      if (invitationCode == null) {
        // 用户取消了
        onCancel?.call();
        setLoading(false);
        return false;
      }
    }

    debugPrint('=== 完成登录 ===');
    try {
      final authResponse = await backend.completeLogin(
        verifyResponse.pendingToken,
        invitationCode: invitationCode,
      );
      debugPrint('后端响应: onboardingCompleted=${authResponse.onboardingCompleted}');

      if (!mounted) return false;

      return await handlePostLogin(authResponse);
    } catch (e) {
      debugPrint('完成登录错误: $e');
      setLoginError(_extractErrorMessage(e));
      setLoading(false);
      return false;
    }
  }

  /// 处理登录成功后的跳转逻辑
  /// [authResponse] - 登录成功后的响应
  /// 返回 true 表示成功，false 表示出错
  Future<bool> handlePostLogin(AuthResponse authResponse) async {
    if (!mounted) return false;

    if (authResponse.onboardingCompleted) {
      // 已完成 onboarding，需要先登录 Matrix
      debugPrint('=== 已完成 onboarding，尝试登录 Matrix ===');
      return await loginMatrixAndRedirect();
    } else {
      // 需要先完成 onboarding
      // PC端：切换到主窗口模式
      if (PlatformInfos.isDesktop) {
        await WindowService.switchToMainWindow();
      }
      setLoading(false);
      context.go('/onboarding-chatbot');
      return true;
    }
  }

  /// 登录 Matrix 并跳转到主页
  Future<bool> loginMatrixAndRedirect() async {
    final matrixAccessToken = backend.auth.matrixAccessToken;
    final matrixUserId = backend.auth.matrixUserId;

    if (matrixAccessToken == null || matrixUserId == null) {
      debugPrint('Matrix access token 缺失，无法登录 Matrix');
      if (mounted) {
        setLoginError('Matrix 凭证缺失，请重新登录');
        setLoading(false);
      }
      return false;
    }

    try {
      final matrix = Matrix.of(context);
      final client = await matrix.getLoginClient();

      // Set homeserver before login
      final homeserverUrl = Uri.parse(PsygoConfig.matrixHomeserver);
      debugPrint('设置 homeserver: $homeserverUrl');
      await client.checkHomeserver(homeserverUrl);

      debugPrint('尝试 Matrix 登录: matrixUserId=$matrixUserId');

      // 使用后端返回的 access_token 直接初始化，无需密码登录
      await client.init(
        newToken: matrixAccessToken,
        newUserID: matrixUserId,
        newHomeserver: homeserverUrl,
        newDeviceName: PlatformInfos.clientName,
      );
      debugPrint('Matrix 登录成功');

      // PC端：切换到主窗口模式
      if (PlatformInfos.isDesktop) {
        await WindowService.switchToMainWindow();
      }

      // 登录成功后异步请求推送权限（不阻塞跳转）
      if (PlatformInfos.isMobile) {
        Future.delayed(const Duration(seconds: 1), () {
          PermissionService.instance.requestPushPermissions();
        });
      }
      // Matrix login success -> auto redirect to /rooms by MatrixState
      return true;
    } catch (e) {
      debugPrint('Matrix 登录失败: $e');
      if (mounted) {
        setLoginError('登录失败: $e');
        setLoading(false);
      }
      return false;
    }
  }

  /// 显示邀请码输入对话框
  /// 返回邀请码，用户取消则返回 null
  Future<String?> showInvitationCodeDialog(String maskedPhone) async {
    final controller = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新用户注册'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手机号：$maskedPhone',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Text('请输入邀请码完成注册'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '邀请码',
                  hintText: '请输入邀请码',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  errorText: errorText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final code = controller.text.trim();
                if (code.isEmpty) {
                  setDialogState(() => errorText = '请输入邀请码');
                  return;
                }
                Navigator.of(context).pop(code);
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  /// 提取干净的错误消息
  String _extractErrorMessage(Object e) {
    if (e is AutomateBackendException) {
      return e.message;
    }
    return e.toString();
  }
}
