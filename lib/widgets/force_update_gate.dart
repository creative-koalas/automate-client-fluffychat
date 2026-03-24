import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/force_update_controller.dart';
import '../utils/platform_infos.dart';

class ForceUpdateGate extends StatelessWidget {
  const ForceUpdateGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ForceUpdateController>();
    if (!controller.hasLoaded) {
      return Stack(
        children: [
          IgnorePointer(
            ignoring: true,
            child: child,
          ),
          const Positioned.fill(
            child: Material(
              color: Colors.black12,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ],
      );
    }
    if (!controller.isRequired) {
      return child;
    }
    if (controller.isShowingUpdateDialog) {
      return child;
    }

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final snapshot = controller.status;
    final latestVersion = snapshot.latestVersion.trim();
    final minVersion = snapshot.minVersion.trim();
    final message = snapshot.message.trim();
    final hasDownloadUrl = snapshot.hasDownloadUrl;

    return Stack(
      children: [
        IgnorePointer(
          ignoring: true,
          child: child,
        ),
        Positioned.fill(
          child: Material(
            color: isDark ? const Color(0xFF0B131A) : const Color(0xFFF4EFE6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF0B131A),
                          Color(0xFF1A2733),
                          Color(0xFF123645),
                        ]
                      : const [
                          Color(0xFFF7F3EA),
                          Color(0xFFEDE7DC),
                          Color(0xFFE1ECE8),
                        ],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFF163A4D).withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFFFFB37A).withValues(alpha: 0.16)
                                : const Color(0xFFE08F47).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.system_update_alt_rounded,
                            size: 34,
                            color: isDark
                                ? const Color(0xFFFFCFA7)
                                : const Color(0xFFB8682B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.authNeedUpdateTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF18242D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.authNeedUpdateMessage,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.78)
                                : const Color(0xFF56626B),
                          ),
                        ),
                        if (latestVersion.isNotEmpty || minVersion.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFF8F5EE),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (latestVersion.isNotEmpty)
                                  Text(
                                    '${l10n.version}: $latestVersion',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.92)
                                          : const Color(0xFF1F2F39),
                                    ),
                                  ),
                                if (minVersion.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Min: $minVersion',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.72)
                                          : const Color(0xFF5A6A74),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.72)
                                  : const Color(0xFF5A6A74),
                            ),
                          ),
                        ],
                        if (!hasDownloadUrl) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.appUpdateDownloadLinkFailed,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: controller.isUpdateActionInFlight
                                ? null
                                : () => controller.openUpdateDialog(context),
                            child: controller.isUpdateActionInFlight
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(l10n.appUpdateNow),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: controller.isRefreshing
                                ? null
                                : () => controller.refreshStatus(),
                            child: controller.isRefreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(l10n.authCheckAgain),
                          ),
                        ),
                        if (PlatformInfos.isDesktop) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: controller.isUpdateActionInFlight
                                  ? null
                                  : () => SystemNavigator.pop(),
                              child: Text(l10n.close),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
