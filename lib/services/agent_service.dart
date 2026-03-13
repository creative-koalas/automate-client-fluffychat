/// Agent 服务（单例）
/// 提供员工列表缓存和查询功能
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../core/config.dart';
import '../models/agent.dart';
import '../repositories/agent_repository.dart';

/// Agent 服务单例
/// 用于在应用中共享员工列表数据
class AgentService {
  static final AgentService _instance = AgentService._internal();
  static AgentService get instance => _instance;

  AgentService._internal();

  final AgentRepository _repository = AgentRepository();

  /// 员工列表缓存
  List<Agent> _agents = [];

  /// Matrix User ID -> Agent 的映射缓存
  final Map<String, Agent> _matrixUserIdToAgent = {};
  final Map<String, _MatrixProfilePresentation>
      _resolvedMemberPresentationByUserId = {};
  final Map<String, _MatrixProfilePresentation> _profilePresentationByUserId =
      {};
  final Set<String> _resolvedMemberLookupInFlight = {};
  final Map<String, DateTime> _resolvedMemberLookupLastAttemptAt = {};
  final Set<String> _pendingResolvedMemberLookupUserIds = {};
  bool _resolvedMemberLookupScheduled = false;
  static const Duration _resolvedMemberLookupCooldown = Duration(minutes: 1);
  final Set<String> _profileLookupInFlight = {};
  final Map<String, DateTime> _profileLookupLastAttemptAt = {};
  static const Duration _profileLookupCooldown = Duration(minutes: 1);
  int _liveStatusWatcherCount = 0;
  Timer? _liveStatusPollingTimer;
  static const Duration _liveStatusPollingInterval = Duration(seconds: 10);

  /// 是否已初始化
  bool _initialized = false;

  /// 是否正在加载
  bool _isLoading = false;

  /// 数据变化通知
  final ValueNotifier<List<Agent>> agentsNotifier = ValueNotifier([]);

  /// 获取所有员工
  List<Agent> get agents => List.unmodifiable(_agents);

  /// 是否已初始化
  bool get initialized => _initialized;

  /// 初始化服务，加载员工列表
  Future<void> init() async {
    if (_initialized || _isLoading) return;

    _isLoading = true;
    try {
      await _loadAllAgents();
      _initialized = true;
    } catch (e) {
      debugPrint('[AgentService] Init failed: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// 加载所有员工（处理分页）
  Future<void> _loadAllAgents({bool forceRefresh = false}) async {
    final allAgents = <Agent>[];
    int? cursor;
    var hasMore = true;

    while (hasMore) {
      final page = await _repository.getUserAgents(
        cursor: cursor,
        limit: 50,
        forceRefresh: forceRefresh,
      );
      allAgents.addAll(page.agents);
      cursor = page.nextCursor;
      hasMore = page.hasNextPage;
    }

    _agents = allAgents;
    _rebuildMatrixUserIdMap();
    _notifyChanged();
    debugPrint('[AgentService] Loaded ${_agents.length} agents');
  }

  /// 重建 Matrix User ID -> Agent 映射
  void _rebuildMatrixUserIdMap() {
    _matrixUserIdToAgent.clear();
    for (final agent in _agents) {
      final key = agent.matrixUserId?.trim() ?? '';
      if (key.isNotEmpty) {
        _matrixUserIdToAgent[key] = agent;
      }
    }
  }

  /// 刷新员工列表
  Future<void> refresh({bool forceRefresh = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    try {
      await _loadAllAgents(forceRefresh: forceRefresh);
    } catch (e) {
      debugPrint('[AgentService] Refresh failed: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// 群聊工作状态实时刷新订阅：
  /// 当至少有一个群聊页面激活时，后台轮询刷新自己的员工状态。
  void attachLiveStatusWatcher() {
    _liveStatusWatcherCount++;
    if (_liveStatusWatcherCount != 1) {
      return;
    }
    unawaited(refresh(forceRefresh: true));
    _liveStatusPollingTimer ??= Timer.periodic(
      _liveStatusPollingInterval,
      (_) => unawaited(refresh(forceRefresh: true)),
    );
  }

  void detachLiveStatusWatcher() {
    if (_liveStatusWatcherCount <= 0) {
      return;
    }
    _liveStatusWatcherCount--;
    if (_liveStatusWatcherCount > 0) {
      return;
    }
    _liveStatusPollingTimer?.cancel();
    _liveStatusPollingTimer = null;
  }

  /// 根据 Matrix User ID 查找员工
  /// 返回 null 表示不是员工
  Agent? getAgentByMatrixUserId(String? matrixUserId) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) return null;
    return _matrixUserIdToAgent[key];
  }

  /// 按 Matrix User ID 解析展示名称
  /// 优先级：自己的员工名称 > 服务端解析缓存 > Matrix profile 缓存 > fallback
  String resolveDisplayNameByMatrixUserId(
    String? matrixUserId, {
    String? fallbackDisplayName,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return '';
    }

    final agent = _matrixUserIdToAgent[key];
    final ownName = _normalizeDisplayNameCandidate(agent?.displayName, key);
    if (ownName != null) {
      return ownName;
    }

    final resolved = _resolvedMemberPresentationByUserId[key];
    final resolvedName =
        _normalizeDisplayNameCandidate(resolved?.displayName, key);
    if (resolvedName != null) {
      return resolvedName;
    }

    final remote = _profilePresentationByUserId[key];
    final remoteName =
        _normalizeDisplayNameCandidate(remote?.displayName, key);
    if (remoteName != null) {
      return remoteName;
    }

    final fallback = _normalizeDisplayNameCandidate(fallbackDisplayName, key);
    if (fallback != null) {
      return fallback;
    }

    return key.localpart ?? key;
  }

  /// 按 Matrix User ID 解析展示头像
  /// 优先级：自己的员工头像 > 服务端解析缓存 > Matrix profile 缓存 > fallback
  Uri? resolveAvatarUriByMatrixUserId(
    String? matrixUserId, {
    Uri? fallbackAvatarUri,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return fallbackAvatarUri;
    }

    final agent = _matrixUserIdToAgent[key];
    final ownAvatar = parseAvatarUri(agent?.avatarUrl);
    if (ownAvatar != null) {
      return ownAvatar;
    }

    final resolved = _resolvedMemberPresentationByUserId[key];
    final resolvedAvatar = parseAvatarUri(resolved?.avatarUrl);
    if (resolvedAvatar != null) {
      return resolvedAvatar;
    }

    final remote = _profilePresentationByUserId[key];
    final remoteAvatar = parseAvatarUri(remote?.avatarUrl);
    if (remoteAvatar != null) {
      return remoteAvatar;
    }

    return fallbackAvatarUri;
  }

  /// 解析 User 的展示名称（含远端 profile 覆盖）
  String resolveDisplayName(User user) {
    return resolveDisplayNameByMatrixUserId(
      user.id,
      fallbackDisplayName: user.calcDisplayname(),
    );
  }

  /// 解析 User 的展示头像（含远端 profile 覆盖）
  Uri? resolveAvatarUri(User user) {
    return resolveAvatarUriByMatrixUserId(
      user.id,
      fallbackAvatarUri: user.avatarUrl,
    );
  }

  /// 懒加载 Matrix 资料（用于非本人员工的昵称/头像展示）
  void ensureMatrixProfilePresentation(User user) {
    ensureMatrixProfilePresentationById(
      client: user.room.client,
      matrixUserId: user.id,
      fallbackDisplayName: user.displayName ?? user.calcDisplayname(),
      fallbackAvatarUri: user.avatarUrl,
    );
  }

  /// 按 Matrix User ID 懒加载 Matrix 资料（带去重与冷却）
  void ensureMatrixProfilePresentationById({
    required Client client,
    required String? matrixUserId,
    String? fallbackDisplayName,
    Uri? fallbackAvatarUri,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return;
    }
    if (_matrixUserIdToAgent.containsKey(key)) {
      return;
    }
    _queueResolvedMemberLookup(key);
    if (_resolvedMemberPresentationByUserId.containsKey(key)) {
      return;
    }
    if (_profileLookupInFlight.contains(key)) {
      return;
    }
    final now = DateTime.now();
    final lastAttemptAt = _profileLookupLastAttemptAt[key];
    if (lastAttemptAt != null &&
        now.difference(lastAttemptAt) < _profileLookupCooldown) {
      return;
    }
    _profileLookupLastAttemptAt[key] = now;
    _profileLookupInFlight.add(key);
    unawaited(
      _loadMatrixProfilePresentation(
        client: client,
        matrixUserId: key,
        fallbackDisplayName: fallbackDisplayName,
        fallbackAvatarUri: fallbackAvatarUri,
      ),
    );
  }

  void _queueResolvedMemberLookup(String matrixUserId) {
    if (_matrixUserIdToAgent.containsKey(matrixUserId)) {
      return;
    }
    if (_resolvedMemberPresentationByUserId.containsKey(matrixUserId)) {
      return;
    }
    if (_resolvedMemberLookupInFlight.contains(matrixUserId)) {
      return;
    }
    final now = DateTime.now();
    final lastAttemptAt = _resolvedMemberLookupLastAttemptAt[matrixUserId];
    if (lastAttemptAt != null &&
        now.difference(lastAttemptAt) < _resolvedMemberLookupCooldown) {
      return;
    }
    _pendingResolvedMemberLookupUserIds.add(matrixUserId);
    if (_resolvedMemberLookupScheduled) {
      return;
    }
    _resolvedMemberLookupScheduled = true;
    scheduleMicrotask(_flushQueuedResolvedMemberLookups);
  }

  Future<void> _flushQueuedResolvedMemberLookups() async {
    _resolvedMemberLookupScheduled = false;
    if (_pendingResolvedMemberLookupUserIds.isEmpty) {
      return;
    }

    final queued = _pendingResolvedMemberLookupUserIds.toList(growable: false);
    _pendingResolvedMemberLookupUserIds.clear();

    final now = DateTime.now();
    final requestIds = <String>[];
    for (final matrixUserId in queued) {
      if (_matrixUserIdToAgent.containsKey(matrixUserId)) {
        continue;
      }
      if (_resolvedMemberPresentationByUserId.containsKey(matrixUserId)) {
        continue;
      }
      if (_resolvedMemberLookupInFlight.contains(matrixUserId)) {
        continue;
      }
      final lastAttemptAt = _resolvedMemberLookupLastAttemptAt[matrixUserId];
      if (lastAttemptAt != null &&
          now.difference(lastAttemptAt) < _resolvedMemberLookupCooldown) {
        continue;
      }
      _resolvedMemberLookupLastAttemptAt[matrixUserId] = now;
      _resolvedMemberLookupInFlight.add(matrixUserId);
      requestIds.add(matrixUserId);
    }

    if (requestIds.isEmpty) {
      return;
    }

    try {
      final resolvedMembers =
          await _repository.resolveMembersByMatrixUserIds(requestIds);
      final resolvedById = <String, ResolvedAgentMember>{
        for (final member in resolvedMembers)
          member.matrixUserId.trim(): member,
      };

      var changed = false;
      for (final matrixUserId in requestIds) {
        final member = resolvedById[matrixUserId];
        if (member == null) {
          continue;
        }

        final displayName = _normalizeDisplayNameCandidate(
          member.displayName,
          matrixUserId,
        );
        final avatarUrl = _normalizeAvatarUrl(member.avatarUrl);
        if (displayName == null && avatarUrl == null) {
          continue;
        }

        final previous = _resolvedMemberPresentationByUserId[matrixUserId];
        if (previous?.displayName == displayName &&
            previous?.avatarUrl == avatarUrl) {
          continue;
        }

        _resolvedMemberPresentationByUserId[matrixUserId] =
            _MatrixProfilePresentation(
          displayName: displayName,
          avatarUrl: avatarUrl,
        );
        changed = true;
      }

      if (changed) {
        _notifyChanged();
      }
    } catch (e) {
      debugPrint('[AgentService] Resolve members failed: $e');
    } finally {
      for (final matrixUserId in requestIds) {
        _resolvedMemberLookupInFlight.remove(matrixUserId);
      }
    }
  }

  Future<void> _loadMatrixProfilePresentation({
    required Client client,
    required String matrixUserId,
    String? fallbackDisplayName,
    Uri? fallbackAvatarUri,
  }) async {
    try {
      final profile = await client.getProfileFromUserId(matrixUserId);

      final displayName = _normalizeDisplayNameCandidate(
            profile.displayName,
            matrixUserId,
          ) ??
          _normalizeDisplayNameCandidate(fallbackDisplayName, matrixUserId);

      final avatarUrl = _normalizeAvatarUrl(profile.avatarUrl?.toString()) ??
          _normalizeAvatarUrl(fallbackAvatarUri?.toString());

      if (displayName == null && avatarUrl == null) {
        return;
      }
      if (_resolvedMemberPresentationByUserId.containsKey(matrixUserId)) {
        return;
      }

      final previous = _profilePresentationByUserId[matrixUserId];
      if (previous?.displayName == displayName &&
          previous?.avatarUrl == avatarUrl) {
        return;
      }

      _profilePresentationByUserId[matrixUserId] = _MatrixProfilePresentation(
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      _notifyChanged();
    } catch (e) {
      debugPrint('[AgentService] Profile lookup failed for $matrixUserId: $e');
    } finally {
      _profileLookupInFlight.remove(matrixUserId);
    }
  }

  String? _normalizeDisplayNameCandidate(String? candidate, String matrixUserId) {
    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == matrixUserId) {
      return null;
    }
    return trimmed;
  }

  String? _normalizeAvatarUrl(String? avatarUrl) {
    final trimmed = avatarUrl?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == 'null') {
      return null;
    }
    return trimmed;
  }

  /// 检查 Matrix User ID 是否是员工
  bool isEmployee(String? matrixUserId) {
    return getAgentByMatrixUserId(matrixUserId) != null;
  }

  /// 安全地获取员工头像 URI
  /// 返回 null 如果不是员工、没有头像或头像 URL 无效
  Uri? getAgentAvatarUri(String? matrixUserId) {
    final agent = getAgentByMatrixUserId(matrixUserId);
    return parseAvatarUri(agent?.avatarUrl);
  }

  /// 获取员工头像和显示名称（用于 Avatar 组件）
  /// 返回 (avatarUri, displayName)，如果不是员工或头像无效则返回 (null, null)
  (Uri?, String?) getAgentAvatarAndName(String? matrixUserId) {
    final agent = getAgentByMatrixUserId(matrixUserId);
    if (agent == null) return (null, null);

    final avatarUri = parseAvatarUri(agent.avatarUrl);
    return (avatarUri, agent.displayName);
  }

  /// 解析员工头像 URL，支持 mxc/http(s) 与相对路径
  Uri? parseAvatarUri(String? avatarUrl) {
    if (avatarUrl == null) return null;
    final trimmed = avatarUrl.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;

    final directUri = Uri.tryParse(trimmed);
    final supportedDirect = _supportedAvatarUri(directUri);
    if (supportedDirect != null) {
      return supportedDirect;
    }

    final fixedScheme = _fixMissingSlashes(directUri, trimmed);
    if (fixedScheme != null) {
      return fixedScheme;
    }

    final normalized = _normalizeAvatarUri(trimmed);
    final supportedNormalized = _supportedAvatarUri(normalized);
    if (supportedNormalized != null) {
      return supportedNormalized;
    }

    debugPrint('[AgentService] Invalid avatar URL: $avatarUrl');
    return null;
  }

  Uri? _supportedAvatarUri(Uri? uri) {
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme == 'http' || scheme == 'https' || scheme == 'mxc') &&
        uri.host.isNotEmpty) {
      return uri;
    }
    return null;
  }

  Uri? _fixMissingSlashes(Uri? uri, String raw) {
    if (uri == null) return null;
    if (uri.host.isNotEmpty) return null;
    if (raw.contains('://')) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https' && scheme != 'mxc') {
      return null;
    }
    final rest = raw.substring(scheme.length + 1);
    return _supportedAvatarUri(Uri.tryParse('$scheme://$rest'));
  }

  Uri? _normalizeAvatarUri(String raw) {
    final baseUri = Uri.parse(PsygoConfig.baseUrl);
    final defaultScheme = baseUri.scheme.isNotEmpty ? baseUri.scheme : 'https';

    if (raw.startsWith('//')) {
      return Uri.tryParse('$defaultScheme:$raw');
    }

    if (_looksLikeHost(raw)) {
      return Uri.tryParse('$defaultScheme://$raw');
    }

    if (raw.startsWith('/')) {
      return Uri.tryParse('${baseUri.origin}$raw');
    }

    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    final baseWithSlash = baseUri.replace(path: basePath);
    return baseWithSlash.resolve(raw);
  }

  bool _looksLikeHost(String value) {
    final stop = value.indexOf(RegExp(r'[/?#]'));
    final hostPart = stop == -1 ? value : value.substring(0, stop);
    return hostPart.contains('.') || hostPart.contains(':');
  }

  /// 更新单个员工信息（用于局部更新）
  void updateAgent(Agent agent) {
    final index = _agents.indexWhere((a) => a.agentId == agent.agentId);
    if (index != -1) {
      _agents[index] = agent;
    } else {
      // Allow late discovery (e.g. direct chat page loads before AgentService.init finished).
      _agents.add(agent);
    }

    if (agent.matrixUserId != null && agent.matrixUserId!.isNotEmpty) {
      final key = agent.matrixUserId!.trim();
      if (key.isNotEmpty) {
        _matrixUserIdToAgent[key] = agent;
      }
    }
    _notifyChanged();
  }

  void _notifyChanged() {
    agentsNotifier.value = List.unmodifiable(_agents);
  }

  /// 释放资源
  void dispose() {
    _liveStatusWatcherCount = 0;
    _liveStatusPollingTimer?.cancel();
    _liveStatusPollingTimer = null;
    _resolvedMemberPresentationByUserId.clear();
    _resolvedMemberLookupInFlight.clear();
    _resolvedMemberLookupLastAttemptAt.clear();
    _pendingResolvedMemberLookupUserIds.clear();
    _resolvedMemberLookupScheduled = false;
    _profilePresentationByUserId.clear();
    _profileLookupInFlight.clear();
    _profileLookupLastAttemptAt.clear();
    _repository.dispose();
    agentsNotifier.dispose();
  }
}

class _MatrixProfilePresentation {
  final String? displayName;
  final String? avatarUrl;

  const _MatrixProfilePresentation({
    this.displayName,
    this.avatarUrl,
  });
}
