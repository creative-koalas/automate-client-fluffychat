import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/maintenance_status_controller.dart';

class MaintenanceGate extends StatelessWidget {
  const MaintenanceGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaintenanceStatusController>();
    if (!controller.isClosed) {
      return child;
    }

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reason = controller.status.reason.trim();

    return Stack(
      children: [
        IgnorePointer(
          ignoring: true,
          child: child,
        ),
        Positioned.fill(
          child: Material(
            color: isDark
                ? const Color(0xFF09131F)
                : const Color(0xFFF4F1EA),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF09131F),
                          Color(0xFF12304A),
                          Color(0xFF1B4D5C),
                        ]
                      : const [
                          Color(0xFFF7F2E7),
                          Color(0xFFE9E6DC),
                          Color(0xFFDDE9E4),
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
                            ? Colors.white.withValues(alpha: 0.14)
                            : const Color(0xFF173A4B).withValues(alpha: 0.10),
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
                                ? const Color(0xFFFA8072).withValues(alpha: 0.14)
                                : const Color(0xFFD06744).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.construction_rounded,
                            size: 34,
                            color: isDark
                                ? const Color(0xFFFFB199)
                                : const Color(0xFFAF4E2E),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.maintenanceBlockedTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF18242D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.maintenanceBlockedMessage,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.76)
                                : const Color(0xFF56626B),
                          ),
                        ),
                        if (reason.isNotEmpty) ...[
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
                                Text(
                                  l10n.maintenanceBlockedReasonLabel,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.78)
                                        : const Color(0xFF374650),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  reason,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.45,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.88)
                                        : const Color(0xFF1F2F39),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
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
