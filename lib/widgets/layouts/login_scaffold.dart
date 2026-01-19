import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:psygo/config/app_config.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/platform_infos.dart';

class LoginScaffold extends StatelessWidget {
  final Widget body;
  final AppBar? appBar;
  final bool enforceMobileMode;

  const LoginScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.enforceMobileMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMobileMode =
        enforceMobileMode || !FluffyThemes.isColumnMode(context);
    if (isMobileMode) {
      return Scaffold(
        key: const Key('LoginScaffold'),
        appBar: appBar,
        body: SafeArea(child: body),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerLow,
            theme.colorScheme.surfaceContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withAlpha(15),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: theme.colorScheme.shadow.withAlpha(20),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.hardEdge,
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: isMobileMode
                          ? const BoxConstraints()
                          : const BoxConstraints(maxWidth: 480, maxHeight: 680),
                      child: Scaffold(
                        key: const Key('LoginScaffold'),
                        appBar: appBar,
                        body: SafeArea(child: body),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const _PrivacyButtons(mainAxisAlignment: MainAxisAlignment.center),
        ],
      ),
    );
  }
}

class _PrivacyButtons extends StatelessWidget {
  final MainAxisAlignment mainAxisAlignment;
  const _PrivacyButtons({required this.mainAxisAlignment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildButton(String text, VoidCallback onPressed) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: mainAxisAlignment,
          children: [
            buildButton(
              L10n.of(context).website,
              () => launchUrlString(AppConfig.website),
            ),
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withAlpha(60),
                shape: BoxShape.circle,
              ),
            ),
            buildButton(
              L10n.of(context).help,
              () => launchUrlString(AppConfig.supportUrl),
            ),
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withAlpha(60),
                shape: BoxShape.circle,
              ),
            ),
            buildButton(
              L10n.of(context).privacy,
              () => launchUrl(AppConfig.privacyUrl),
            ),
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withAlpha(60),
                shape: BoxShape.circle,
              ),
            ),
            buildButton(
              L10n.of(context).about,
              () => PlatformInfos.showDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
