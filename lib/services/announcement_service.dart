import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/core/api_client.dart';
import 'package:psygo/models/announcement.dart';
import 'package:psygo/utils/platform_infos.dart';

class AnnouncementService {
  AnnouncementService._();

  static final AnnouncementService instance = AnnouncementService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _stateKeyPrefix = 'automate_announcement_state_v1_';
  static const String _logPrefix = '[Announcement]';

  final PsygoApiClient _apiClient = PsygoApiClient();
  final Set<String> _impressionTrackedInSession = <String>{};
  final Set<String> _dismissedInSession = <String>{};
  final Map<String, _AnnouncementDisplayState> _memoryCache = {};

  Future<Announcement?> fetchActiveAnnouncement({
    required String? userId,
    String scene = 'chat_list',
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      Logs().w('$_logPrefix skip fetch: empty userId');
      return null;
    }

    final platform = PlatformInfos.platformName;
    Logs().i('$_logPrefix fetch active start scene=$scene platform=$platform');

    dynamic payload;
    try {
      final response = await _apiClient.get<dynamic>(
        '/api/announcements/active',
        queryParameters: {
          'scene': scene,
          'platform': platform,
        },
        fromJsonT: (data) => data,
      );
      if (!response.isSuccess) {
        Logs().w(
          '$_logPrefix fetch active failed code=${response.code} message=${response.message}',
        );
        return null;
      }
      payload = response.data;
    } catch (e, s) {
      Logs().e('$_logPrefix fetch active exception', e, s);
      return null;
    }

    final now = DateTime.now();
    final extracted = _extractAnnouncements(payload);
    final sceneMatched =
        extracted.where((announcement) => announcement.supportsScene(scene)).toList();
    final platformMatched = sceneMatched
        .where((announcement) => announcement.matchesPlatform())
        .toList();
    final activeTimeMatched = platformMatched
        .where((announcement) => announcement.isActiveAt(now))
        .toList();
    final announcements = activeTimeMatched
        .where((announcement) => !_dismissedInSession.contains(announcement.id))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    Logs().i(
      '$_logPrefix candidates extracted=${extracted.length} scene=${sceneMatched.length} platform=${platformMatched.length} activeTime=${activeTimeMatched.length} session=${announcements.length}',
    );

    for (final announcement in announcements) {
      final displayState =
          await _loadDisplayState(normalizedUserId, announcement.id);
      if (_canDisplay(announcement, displayState, now)) {
        Logs().i(
          '$_logPrefix selected id=${announcement.id} impressionCount=${displayState.impressionCount}/${announcement.maxImpressions}',
        );
        return announcement;
      }
      Logs().i(
        '$_logPrefix skip id=${announcement.id} reason=${_displayBlockReason(announcement, displayState, now)} impressionCount=${displayState.impressionCount}/${announcement.maxImpressions} minIntervalHours=${announcement.minIntervalHours}',
      );
    }
    Logs().i('$_logPrefix no displayable announcement');
    return null;
  }

  Future<void> trackImpression({
    required Announcement announcement,
    required String? userId,
    String scene = 'chat_list',
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      Logs().w('$_logPrefix skip impression: empty userId id=${announcement.id}');
      return;
    }
    if (_impressionTrackedInSession.contains(announcement.id)) {
      Logs().i('$_logPrefix skip impression: already tracked id=${announcement.id}');
      return;
    }

    final now = DateTime.now().toUtc();
    final state = await _loadDisplayState(normalizedUserId, announcement.id);
    if (state.impressionCount >= announcement.maxImpressions) {
      Logs().i(
        '$_logPrefix skip impression: max reached id=${announcement.id} count=${state.impressionCount}/${announcement.maxImpressions}',
      );
      return;
    }

    final nextState = state.copyWith(
      impressionCount: state.impressionCount + 1,
      lastImpressionAt: now,
    );
    await _saveDisplayState(normalizedUserId, announcement.id, nextState);
    _impressionTrackedInSession.add(announcement.id);
    await _trackEvent(
      announcementId: announcement.id,
      scene: scene,
      eventType: AnnouncementEventType.impression,
      occurredAt: now,
    );
    Logs().i('$_logPrefix tracked impression id=${announcement.id}');
  }

  Future<void> trackDismiss({
    required String announcementId,
    String scene = 'chat_list',
  }) async {
    _dismissedInSession.add(announcementId);
    await _trackEvent(
      announcementId: announcementId,
      scene: scene,
      eventType: AnnouncementEventType.dismiss,
      occurredAt: DateTime.now().toUtc(),
    );
    Logs().i('$_logPrefix tracked dismiss id=$announcementId');
  }

  Future<void> trackClick({
    required String announcementId,
    String scene = 'chat_list',
  }) async {
    await _trackEvent(
      announcementId: announcementId,
      scene: scene,
      eventType: AnnouncementEventType.click,
      occurredAt: DateTime.now().toUtc(),
    );
    Logs().i('$_logPrefix tracked click id=$announcementId');
  }

  Future<void> trackAcknowledge({
    required String announcementId,
    String scene = 'chat_list',
  }) async {
    await _trackEvent(
      announcementId: announcementId,
      scene: scene,
      eventType: AnnouncementEventType.acknowledge,
      occurredAt: DateTime.now().toUtc(),
    );
    Logs().i('$_logPrefix tracked acknowledge id=$announcementId');
  }

  bool _canDisplay(
    Announcement announcement,
    _AnnouncementDisplayState state,
    DateTime now,
  ) {
    if (state.impressionCount >= announcement.maxImpressions) {
      return false;
    }
    final hours = announcement.minIntervalHours;
    if (hours <= 0) {
      return true;
    }
    final last = state.lastImpressionAt;
    if (last == null) {
      return true;
    }
    return now.difference(last.toLocal()) >= Duration(hours: hours);
  }

  String _displayBlockReason(
    Announcement announcement,
    _AnnouncementDisplayState state,
    DateTime now,
  ) {
    if (state.impressionCount >= announcement.maxImpressions) {
      return 'max_impressions';
    }
    final hours = announcement.minIntervalHours;
    if (hours <= 0) {
      return 'unknown';
    }
    final last = state.lastImpressionAt;
    if (last == null) {
      return 'unknown';
    }
    final elapsed = now.difference(last.toLocal());
    if (elapsed < Duration(hours: hours)) {
      return 'min_interval';
    }
    return 'unknown';
  }

  List<Announcement> _extractAnnouncements(dynamic payload) {
    final raw = payload;
    final list = <dynamic>[];

    if (raw is List) {
      list.addAll(raw);
    } else if (raw is Map<String, dynamic>) {
      final announcements = raw['announcements'];
      final announcement = raw['announcement'];
      if (announcements is List) {
        list.addAll(announcements);
      } else if (announcement is Map<String, dynamic>) {
        list.add(announcement);
      } else {
        // 兼容 data 本身就是单条公告对象。
        if (raw.containsKey('announcement_id') || raw.containsKey('id')) {
          list.add(raw);
        }
      }
    } else if (raw is Map) {
      return _extractAnnouncements(raw.cast<String, dynamic>());
    }

    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map((e) {
          try {
            return Announcement.fromJson(e);
          } catch (err, stack) {
            Logs().w('$_logPrefix invalid payload item: $err');
            Logs().d('$_logPrefix invalid payload item stack', err, stack);
            return null;
          }
        })
        .whereType<Announcement>()
        .toList();
  }

  Future<void> _trackEvent({
    required String announcementId,
    required String scene,
    required AnnouncementEventType eventType,
    required DateTime occurredAt,
  }) async {
    try {
      await _apiClient.post<dynamic>(
        '/api/announcements/$announcementId/events',
        body: {
          'event_type': eventType.wireValue,
          'scene': scene,
          'platform': PlatformInfos.platformName,
          'occurred_at': occurredAt.toIso8601String(),
        },
        fromJsonT: (data) => data,
      );
    } catch (e, s) {
      // Ignore event tracking failures to avoid blocking UI.
      Logs().w(
        '$_logPrefix track event failed id=$announcementId type=${eventType.wireValue} scene=$scene platform=${PlatformInfos.platformName}',
      );
      Logs().d('$_logPrefix track event failed stack', e, s);
    }
  }

  Future<_AnnouncementDisplayState> _loadDisplayState(
    String userId,
    String announcementId,
  ) async {
    final key = _storageKey(userId, announcementId);
    final memory = _memoryCache[key];
    if (memory != null) {
      return memory;
    }

    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return const _AnnouncementDisplayState();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final state = _AnnouncementDisplayState.fromJson(decoded);
        _memoryCache[key] = state;
        return state;
      }
      if (decoded is Map) {
        final state =
            _AnnouncementDisplayState.fromJson(decoded.cast<String, dynamic>());
        _memoryCache[key] = state;
        return state;
      }
    } catch (e, s) {
      // Ignore malformed cache.
      Logs().w('$_logPrefix malformed local state key=$key error=$e');
      Logs().d('$_logPrefix malformed local state stack', e, s);
    }

    return const _AnnouncementDisplayState();
  }

  Future<void> _saveDisplayState(
    String userId,
    String announcementId,
    _AnnouncementDisplayState state,
  ) async {
    final key = _storageKey(userId, announcementId);
    _memoryCache[key] = state;
    await _storage.write(key: key, value: jsonEncode(state.toJson()));
  }

  String _storageKey(String userId, String announcementId) {
    return '$_stateKeyPrefix${userId}_$announcementId';
  }
}

class _AnnouncementDisplayState {
  const _AnnouncementDisplayState({
    this.impressionCount = 0,
    this.lastImpressionAt,
  });

  final int impressionCount;
  final DateTime? lastImpressionAt;

  factory _AnnouncementDisplayState.fromJson(Map<String, dynamic> json) {
    final rawCount = json['impression_count'];
    final rawLastAt = json['last_impression_at'];
    return _AnnouncementDisplayState(
      impressionCount: rawCount is int
          ? rawCount
          : rawCount is num
              ? rawCount.toInt()
              : int.tryParse(rawCount?.toString() ?? '') ?? 0,
      lastImpressionAt: rawLastAt is String ? DateTime.tryParse(rawLastAt) : null,
    );
  }

  _AnnouncementDisplayState copyWith({
    int? impressionCount,
    DateTime? lastImpressionAt,
  }) {
    return _AnnouncementDisplayState(
      impressionCount: impressionCount ?? this.impressionCount,
      lastImpressionAt: lastImpressionAt ?? this.lastImpressionAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'impression_count': impressionCount,
        if (lastImpressionAt != null)
          'last_impression_at': lastImpressionAt!.toIso8601String(),
      };
}
