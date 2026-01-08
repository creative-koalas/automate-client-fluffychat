import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:psygo/backend/api_client.dart';
import 'package:psygo/config/app_config.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/app_update_service.dart';
import 'package:psygo/utils/app_update_test.dart';
import 'package:psygo/utils/fluffy_share.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/avatar.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  /// 检查更新
  Future<void> _checkForUpdate(BuildContext context) async {
    final api = context.read<PsygoApiClient>();
    final updateService = AppUpdateService(api);
    // showNoUpdateHint 为 true 表示没有更新时也提示
    await updateService.checkAndPrompt(context, showNoUpdateHint: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).clientOrNull;

    // 如果客户端已经退出，显示空白或加载状态
    if (client == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 主题切换后，GoRouter 的路由信息可能被缓存，导致高亮状态错误
    // 改用更可靠的方式：只在用户点击后短暂高亮，不依赖路由状态
    final accountManageUrl = client
        .wellKnown
        ?.additionalProperties
        .tryGetMap<String, Object?>('org.matrix.msc2965.authentication')
        ?.tryGet<String>('account');
    return Row(
      children: [
        Expanded(
          child: Scaffold(
            appBar: AppBar(
              title: Text(L10n.of(context).settings),
              leading: Center(
                child: BackButton(
                  onPressed: () => context.go('/rooms'),
                ),
              ),
              automaticallyImplyLeading: false,
            ),
            body: ListTileTheme(
              iconColor: theme.colorScheme.onSurface,
              child: ListView(
                key: const Key('SettingsListViewContent'),
                children: <Widget>[
                  FutureBuilder<Profile>(
                    future: controller.profileFuture,
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      final avatar = profile?.avatarUrl;
                      final mxid = Matrix.of(context).client.userID ??
                          L10n.of(context).user;
                      final displayname =
                          profile?.displayName ?? mxid.localpart ?? mxid;
                      return Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Stack(
                              children: [
                                Avatar(
                                  mxContent: avatar,
                                  name: displayname,
                                  size: Avatar.defaultSize * 2.5,
                                  onTap: avatar != null
                                      ? () => showDialog(
                                            context: context,
                                            builder: (_) =>
                                                MxcImageViewer(avatar),
                                          )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 显示昵称（不可编辑）
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    displayname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      FluffyShare.share(mxid, context),
                                  icon: const Icon(
                                    Icons.copy_outlined,
                                    size: 14,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.secondary,
                                    iconColor: theme.colorScheme.secondary,
                                  ),
                                  label: Text(
                                    mxid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    //    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (accountManageUrl != null)
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(L10n.of(context).manageAccount),
                      trailing: const Icon(Icons.open_in_new_outlined),
                      onTap: () => launchUrlString(
                        accountManageUrl,
                        mode: LaunchMode.inAppBrowserView,
                      ),
                    ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    leading: const Icon(Icons.format_paint_outlined),
                    title: Text(L10n.of(context).changeTheme),
                    onTap: () => context.go('/rooms/settings/style'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(L10n.of(context).notifications),
                    onTap: () => context.go('/rooms/settings/notifications'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(L10n.of(context).chat),
                    onTap: () => context.go('/rooms/settings/chat'),
                  ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    leading: const Icon(Icons.feedback_outlined),
                    title: const Text('意见反馈'),
                    onTap: controller.submitFeedbackAction,
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('隐私政策'),
                    onTap: () => launchUrlString(
                      AppConfig.privacyUrl.toString(),
                      mode: LaunchMode.inAppBrowserView,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(L10n.of(context).about),
                    onTap: () => PlatformInfos.showDialog(context),
                  ),
                  Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final isDesktop = screenWidth > 600;
                      return ListTile(
                        leading: Icon(
                          isDesktop
                              ? Icons.downloading_rounded
                              : Icons.system_update_outlined,
                        ),
                        title: const Text('检查更新'),
                        onTap: () => _checkForUpdate(context),
                      );
                    },
                  ),
                  // 仅在调试模式下显示更新UI测试入口
                  if (kDebugMode)
                    ListTile(
                      leading: const Icon(Icons.bug_report_outlined),
                      title: const Text('测试更新弹窗'),
                      subtitle: const Text('预览应用更新UI效果'),
                      onTap: () => AppUpdateTest.showTestDialog(context),
                    ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    leading: Icon(
                      Icons.logout_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      L10n.of(context).logout,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    onTap: controller.logoutAction,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      '注销账号',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    subtitle: const Text('永久删除账号及所有数据'),
                    onTap: controller.deleteAccountAction,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
