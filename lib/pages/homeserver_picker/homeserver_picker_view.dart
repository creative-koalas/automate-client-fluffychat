import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/widgets/layouts/login_scaffold.dart';
import 'package:psygo/widgets/matrix.dart';
import 'homeserver_picker.dart';

class HomeserverPickerView extends StatelessWidget {
  final HomeserverPickerController controller;

  const HomeserverPickerView(
    this.controller, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      enforceMobileMode:
          Matrix.of(context).widget.clients.any((client) => client.isLogged()),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          controller.widget.addMultiAccount
              ? L10n.of(context).addAccount
              : L10n.of(context).login,
        ),
        actions: [
          PopupMenuButton<MoreLoginActions>(
            useRootNavigator: true,
            onSelected: controller.onMoreAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: MoreLoginActions.importBackup,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.import_export_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).hydrate),
                  ],
                ),
              ),
              PopupMenuItem(
                value: MoreLoginActions.privacy,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.privacy_tip_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).privacy),
                  ],
                ),
              ),
              PopupMenuItem(
                value: MoreLoginActions.about,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).about),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Hero(
                        tag: 'info-logo',
                        child: Image.asset(
                          './assets/banner_transparent.png',
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: SelectableLinkify(
                        text: L10n.of(context).appIntroduction,
                        textScaleFactor:
                            MediaQuery.textScalerOf(context).scale(1),
                        textAlign: TextAlign.center,
                        linkStyle: TextStyle(
                          color: theme.colorScheme.secondary,
                          decorationColor: theme.colorScheme.secondary,
                        ),
                        onOpen: (link) => launchUrlString(link.url),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Homeserver 已写死，显示只读信息
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.dns_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        L10n.of(context).homeserver,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        controller.homeserverController.text,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                          // 显示错误信息
                          if (controller.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                controller.error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 12,
                                ),
                                maxLines: 4,
                              ),
                            ),
                          const SizedBox(height: 32),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: controller.isLoading
                                ? null
                                : () => controller.checkHomeserverAction(
                                      legacyPasswordLogin: true,
                                    ),
                            child: controller.isLoading
                                ? const LinearProgressIndicator()
                                : Text(L10n.of(context).login),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
