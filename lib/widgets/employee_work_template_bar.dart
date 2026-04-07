import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:psygo/widgets/horizontal_wheel_scroll_view.dart';

class EmployeeWorkTemplateItem {
  final IconData icon;
  final String title;
  final String description;
  final String message;

  const EmployeeWorkTemplateItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.message,
  });
}

class EmployeeWorkTemplateBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<EmployeeWorkTemplateItem> templates;
  final ValueChanged<EmployeeWorkTemplateItem> onTemplateTap;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onClose;

  const EmployeeWorkTemplateBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.templates,
    required this.onTemplateTap,
    this.margin,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelStartColor = isDark
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.42)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.72);
    final panelEndColor = isDark
        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.28)
        : theme.colorScheme.secondaryContainer.withValues(alpha: 0.58);
    final panelBorderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.42 : 0.28,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 900;

        return Container(
          margin: margin ?? const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: EdgeInsets.all(isWideLayout ? 18 : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [panelStartColor, panelEndColor],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: panelBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: isWideLayout ? 40 : 34,
                    height: isWideLayout ? 40 : 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.assignment_rounded,
                      size: isWideLayout ? 22 : 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (isWideLayout)
                Row(
                  children: [
                    for (var i = 0; i < templates.length; i++) ...[
                      Expanded(
                        child: _EmployeeWorkTemplateCard(
                          template: templates[i],
                          onTap: () => onTemplateTap(templates[i]),
                          isWideLayout: true,
                        ),
                      ),
                      if (i != templates.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                )
              else
                SizedBox(
                  height: 84,
                  child: HorizontalWheelScrollView(
                    scrollBehavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < templates.length; i++) ...[
                          _EmployeeWorkTemplateCard(
                            template: templates[i],
                            onTap: () => onTemplateTap(templates[i]),
                          ),
                          if (i != templates.length - 1)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmployeeWorkTemplateCard extends StatelessWidget {
  final EmployeeWorkTemplateItem template;
  final VoidCallback onTap;
  final bool isWideLayout;

  const _EmployeeWorkTemplateCard({
    required this.template,
    required this.onTap,
    this.isWideLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.94)
        : theme.colorScheme.surface.withValues(alpha: 0.9);
    final cardBorderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.42 : 0.6,
    );
    final iconContainerColor = isDark
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
        : theme.colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: isWideLayout ? null : 200,
      child: Material(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorderColor),
        ),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(isWideLayout ? 16 : 10),
            child: Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: isWideLayout ? 38 : 32,
                    height: isWideLayout ? 38 : 32,
                    decoration: BoxDecoration(
                      color: iconContainerColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      template.icon,
                      size: isWideLayout ? 20 : 17,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: isWideLayout ? 14 : 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          template.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> showEmployeeWorkTemplatePreviewDialog({
  required BuildContext context,
  required EmployeeWorkTemplateItem template,
  required String previewLabel,
  required String sendLabel,
  required String cancelLabel,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final previewSurfaceColor = isDark
      ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92)
      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);

  return showAdaptiveDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog.adaptive(
        title: Text(template.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previewLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: previewSurfaceColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    template.message,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(sendLabel),
          ),
        ],
      );
    },
  );
}
