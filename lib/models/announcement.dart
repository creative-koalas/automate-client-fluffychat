import 'package:psygo/utils/platform_infos.dart';

enum AnnouncementEventType {
  impression('impression'),
  click('click'),
  dismiss('dismiss'),
  acknowledge('acknowledge');

  const AnnouncementEventType(this.wireValue);
  final String wireValue;
}

class Announcement {
  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.targetPlatforms,
    required this.maxImpressions,
    required this.minIntervalHours,
    required this.priority,
    required this.scene,
    this.actionLabel,
    this.actionUrl,
    this.startAt,
    this.endAt,
    this.requireAck = false,
    this.dismissible = true,
  });

  final String id;
  final String title;
  final String body;
  final List<String> targetPlatforms;
  final int maxImpressions;
  final int minIntervalHours;
  final int priority;
  final String scene;
  final String? actionLabel;
  final String? actionUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool requireAck;
  final bool dismissible;

  factory Announcement.fromJson(Map<String, dynamic> json) {
    int readInt(String key, {required int fallback}) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    bool readBool(String key, {required bool fallback}) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value.toLowerCase() == 'true';
      return fallback;
    }

    DateTime? readDateTime(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }

    List<String> readTargetPlatforms() {
      final allPlatforms = readBool('all_platforms', fallback: false);
      if (allPlatforms) {
        return const ['all'];
      }
      final raw = json['target_platforms'] ?? json['platforms'];
      if (raw is List) {
        final platforms = raw
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
        if (platforms.isNotEmpty) {
          return platforms;
        }
      }
      return const ['all'];
    }

    final id = (json['announcement_id'] ?? json['id'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    final body = (json['body'] ?? json['content'] ?? json['message'] ?? '')
        .toString()
        .trim();

    if (id.isEmpty) {
      throw const FormatException('Announcement id is required');
    }

    return Announcement(
      id: id,
      title: title.isNotEmpty ? title : body,
      body: body,
      targetPlatforms: readTargetPlatforms(),
      maxImpressions:
          (readInt('max_impressions', fallback: 3).clamp(1, 99) as num).toInt(),
      minIntervalHours: (readInt('min_interval_hours', fallback: 0)
              .clamp(0, 720) as num)
          .toInt(),
      priority: readInt('priority', fallback: 0),
      scene:
          (json['scene'] ?? json['placement'] ?? 'chat_list').toString().trim(),
      actionLabel: (json['action_label'] ?? json['cta_text'])?.toString(),
      actionUrl: (json['action_url'] ?? json['cta_url'])?.toString(),
      startAt: readDateTime('start_at'),
      endAt: readDateTime('end_at'),
      requireAck: readBool('require_ack', fallback: false),
      dismissible: readBool('dismissible', fallback: true),
    );
  }

  bool isActiveAt(DateTime now) {
    if (startAt != null && now.isBefore(startAt!)) {
      return false;
    }
    if (endAt != null && now.isAfter(endAt!)) {
      return false;
    }
    return true;
  }

  bool supportsScene(String targetScene) {
    final normalizedScene = scene.trim().toLowerCase();
    final normalizedTarget = targetScene.trim().toLowerCase();
    return normalizedScene.isEmpty ||
        normalizedScene == 'all' ||
        normalizedScene == normalizedTarget;
  }

  bool matchesPlatform([String? currentPlatform]) {
    final platform = (currentPlatform ?? PlatformInfos.platformName)
        .trim()
        .toLowerCase();
    return targetPlatforms.contains('all') || targetPlatforms.contains(platform);
  }

  Map<String, dynamic> toJson() => {
        'announcement_id': id,
        'title': title,
        'body': body,
        'target_platforms': targetPlatforms,
        'max_impressions': maxImpressions,
        'min_interval_hours': minIntervalHours,
        'priority': priority,
        'scene': scene,
        if (actionLabel != null) 'action_label': actionLabel,
        if (actionUrl != null) 'action_url': actionUrl,
        if (startAt != null) 'start_at': startAt!.toIso8601String(),
        if (endAt != null) 'end_at': endAt!.toIso8601String(),
        'require_ack': requireAck,
        'dismissible': dismissible,
      };
}
