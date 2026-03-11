import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:psygo/core/api_client.dart';

class OnboardingGuideState {
  const OnboardingGuideState({
    required this.recruit,
    required this.employeeChatRoom,
    required this.groupChat,
    required this.employeeWorkTemplateDismissed,
  });

  final bool recruit;
  final bool employeeChatRoom;
  final bool groupChat;
  final bool employeeWorkTemplateDismissed;

  factory OnboardingGuideState.fromJson(Map<String, dynamic> json) {
    bool readBool(String key) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    return OnboardingGuideState(
      recruit: readBool('recruit'),
      employeeChatRoom: readBool('employee_chat_room'),
      groupChat: readBool('group_chat'),
      employeeWorkTemplateDismissed:
          readBool('employee_work_template_dismissed'),
    );
  }

  Map<String, dynamic> toJson() => {
        'recruit': recruit,
        'employee_chat_room': employeeChatRoom,
        'group_chat': groupChat,
        'employee_work_template_dismissed': employeeWorkTemplateDismissed,
      };
}

class OnboardingGuideService {
  OnboardingGuideService._();

  static final OnboardingGuideService instance = OnboardingGuideService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _cacheKeyPrefix = 'automate_onboarding_guides_cache_v1_';

  final PsygoApiClient _apiClient = PsygoApiClient();
  final Map<String, OnboardingGuideState> _memoryCache = {};

  Future<OnboardingGuideState?> getState(String? userId) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return null;
    }

    final cached = _memoryCache[normalizedUserId];
    if (cached != null) {
      return cached;
    }

    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/users/$normalizedUserId/onboarding-guides',
        fromJsonT: (data) => data as Map<String, dynamic>,
      );
      final state = _extractState(response.data);
      if (state == null) {
        return await _loadFromStorage(normalizedUserId);
      }
      await _saveCache(normalizedUserId, state);
      return state;
    } catch (_) {
      return await _loadFromStorage(normalizedUserId);
    }
  }

  Future<OnboardingGuideState?> updateState(
    String? userId, {
    bool? recruit,
    bool? employeeChatRoom,
    bool? groupChat,
    bool? employeeWorkTemplateDismissed,
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return null;
    }

    final body = <String, dynamic>{};
    if (recruit != null) {
      body['recruit'] = recruit;
    }
    if (employeeChatRoom != null) {
      body['employee_chat_room'] = employeeChatRoom;
    }
    if (groupChat != null) {
      body['group_chat'] = groupChat;
    }
    if (employeeWorkTemplateDismissed != null) {
      body['employee_work_template_dismissed'] = employeeWorkTemplateDismissed;
    }

    if (body.isEmpty) {
      return getState(normalizedUserId);
    }

    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/users/$normalizedUserId/onboarding-guides',
        body: body,
        fromJsonT: (data) => data as Map<String, dynamic>,
      );
      final state = _extractState(response.data);
      if (state != null) {
        await _saveCache(normalizedUserId, state);
        return state;
      }
    } catch (_) {
      // Ignore network errors and keep using last cached value.
    }

    return _memoryCache[normalizedUserId] ??
        await _loadFromStorage(normalizedUserId);
  }

  OnboardingGuideState? _extractState(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }

    final rawGuides = payload['onboarding_guides'];
    if (rawGuides is Map<String, dynamic>) {
      return OnboardingGuideState.fromJson(rawGuides);
    }

    if (rawGuides is Map) {
      return OnboardingGuideState.fromJson(
        rawGuides.cast<String, dynamic>(),
      );
    }

    if (payload.containsKey('recruit') ||
        payload.containsKey('employee_chat_room') ||
        payload.containsKey('group_chat') ||
        payload.containsKey('employee_work_template_dismissed')) {
      return OnboardingGuideState.fromJson(payload);
    }

    return null;
  }

  Future<void> _saveCache(String userId, OnboardingGuideState state) async {
    _memoryCache[userId] = state;
    await _storage.write(
      key: '$_cacheKeyPrefix$userId',
      value: jsonEncode(state.toJson()),
    );
  }

  Future<OnboardingGuideState?> _loadFromStorage(String userId) async {
    final raw = await _storage.read(key: '$_cacheKeyPrefix$userId');
    if (raw == null || raw.isEmpty) {
      return _memoryCache[userId];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final state = OnboardingGuideState.fromJson(decoded);
        _memoryCache[userId] = state;
        return state;
      }
      if (decoded is Map) {
        final state = OnboardingGuideState.fromJson(
          decoded.cast<String, dynamic>(),
        );
        _memoryCache[userId] = state;
        return state;
      }
    } catch (_) {
      // Ignore invalid cache payload.
    }

    return _memoryCache[userId];
  }
}
