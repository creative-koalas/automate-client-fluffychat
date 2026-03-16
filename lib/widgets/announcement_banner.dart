import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/models/announcement.dart';

class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    this.onActionTap,
    this.onDismiss,
    this.onImpression,
  });

  final Announcement announcement;
  final VoidCallback? onActionTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onImpression;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  static const Duration _impressionDelay = Duration(seconds: 1);
  Timer? _impressionTimer;
  bool _impressionTracked = false;

  @override
  void initState() {
    super.initState();
    _scheduleImpression();
  }

  @override
  void didUpdateWidget(covariant AnnouncementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.id != widget.announcement.id) {
      _impressionTimer?.cancel();
      _impressionTracked = false;
      _scheduleImpression();
    }
  }

  @override
  void dispose() {
    _impressionTimer?.cancel();
    super.dispose();
  }

  void _scheduleImpression() {
    _impressionTimer = Timer(_impressionDelay, () {
      if (!mounted || _impressionTracked) return;
      _impressionTracked = true;
      widget.onImpression?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final announcement = widget.announcement;

    final hasAction = (announcement.actionLabel?.trim().isNotEmpty ?? false) &&
        (announcement.actionUrl?.trim().isNotEmpty ?? false);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  announcement.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (announcement.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    announcement.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.9),
                    ),
                  ),
                ],
                if (hasAction) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onActionTap,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      foregroundColor: theme.colorScheme.primary,
                    ),
                    child: Text(
                      announcement.actionLabel!.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (announcement.dismissible)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: widget.onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}
