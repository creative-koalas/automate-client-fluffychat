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
  final Map<String, Agent> _matrixLocalpartToAgent = {};
  final Map<String, _MatrixProfilePresentation> _profilePresentationByUserId =
      {};
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
  DateTime? _lastLoadedAt;
  static const Duration _refreshDedupWindow = Duration(seconds: 3);

  /// 数据变化通知
  final ValueNotifier<List<Agent>> agentsNotifier = ValueNotifier([]);

  /// Profile 加载完成通知（递增计数器，用于触发 mention pill 重建）
  final ValueNotifier<int> profileNotifier = ValueNotifier(0);

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
    final previousCount = _agents.length;
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
    _lastLoadedAt = DateTime.now().toUtc();
    _notifyChanged();
    if (previousCount != _agents.length) {
      debugPrint('[AgentService] Loaded ${_agents.length} agents');
    }
  }

  /// 重建 Matrix User ID -> Agent 映射
  void _rebuildMatrixUserIdMap() {
    _matrixUserIdToAgent.clear();
    _matrixLocalpartToAgent.clear();
    for (final agent in _agents) {
      final key = agent.matrixUserId?.trim() ?? '';
      if (key.isNotEmpty) {
        _matrixUserIdToAgent[key] = agent;
        final localpart = key.localpart?.trim() ?? '';
        if (localpart.isNotEmpty) {
          _matrixLocalpartToAgent[localpart] = agent;
        }
      }
    }
  }

  /// 刷新员工列表
  Future<void> refresh({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final lastLoadedAt = _lastLoadedAt;
      if (lastLoadedAt != null &&
          DateTime.now().toUtc().difference(lastLoadedAt) <
              _refreshDedupWindow) {
        return;
      }
    }
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
    final exact = _matrixUserIdToAgent[key];
    if (exact != null) {
      return exact;
    }
    final localpart = key.localpart?.trim() ?? '';
    if (localpart.isEmpty) {
      return null;
    }
    return _matrixLocalpartToAgent[localpart];
  }

  /// 按 Matrix User ID 解析展示名称
  /// 优先级：自己的员工名称 > Matrix profile 缓存 > fallback
  String? tryResolveDisplayNameByMatrixUserId(
    String? matrixUserId, {
    String? fallbackDisplayName,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return null;
    }

    final agent = getAgentByMatrixUserId(key);
    final ownName = _normalizeDisplayNameCandidate(agent?.displayName, key);
    if (ownName != null) {
      return ownName;
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

    return null;
  }

  /// 按 Matrix User ID 解析展示名称
  /// 优先级：自己的员工名称 > Matrix profile 缓存 > fallback > localpart
  String resolveDisplayNameByMatrixUserId(
    String? matrixUserId, {
    String? fallbackDisplayName,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return '';
    }

    final resolved = tryResolveDisplayNameByMatrixUserId(
      key,
      fallbackDisplayName: fallbackDisplayName,
    );
    if (resolved != null) {
      return resolved;
    }

    return key.localpart ?? key;
  }

  /// 按 Matrix User ID 解析展示头像
  /// 优先级：自己的员工头像 > Matrix profile 缓存 > fallback
  Uri? resolveAvatarUriByMatrixUserId(
    String? matrixUserId, {
    Uri? fallbackAvatarUri,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return fallbackAvatarUri;
    }

    final agent = getAgentByMatrixUserId(key);
    final ownAvatar = parseAvatarUri(agent?.avatarUrl);
    if (ownAvatar != null) {
      return ownAvatar;
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

  /// 严格展示名称（用于常规 UI）：
  /// 仅显示自己的员工名；自己账号显示自身昵称；其余显示 Matrix localpart。
  String resolveStrictDisplayName(User user) {
    final matrixUserId = user.id.trim();
    if (matrixUserId.isEmpty) {
      return '';
    }

    final agent = getAgentByMatrixUserId(matrixUserId);
    final ownAgentName =
        _normalizeDisplayNameCandidate(agent?.displayName, matrixUserId);
    if (ownAgentName != null) {
      return ownAgentName;
    }

    final selfMatrixUserId = user.room.client.userID?.trim() ?? '';
    if (selfMatrixUserId.isNotEmpty && selfMatrixUserId == matrixUserId) {
      final selfName = _normalizeDisplayNameCandidate(
        user.displayName ?? user.calcDisplayname(),
        matrixUserId,
      );
      if (selfName != null) {
        return selfName;
      }
    }

    return matrixUserId.localpart ?? matrixUserId;
  }

  /// 严格展示名称（按 Matrix User ID）。
  String resolveStrictDisplayNameByMatrixUserId(
    String? matrixUserId, {
    String? fallbackDisplayName,
    String? selfMatrixUserId,
  }) {
    final key = matrixUserId?.trim() ?? '';
    if (key.isEmpty) {
      return '';
    }

    final agent = getAgentByMatrixUserId(key);
    final ownAgentName = _normalizeDisplayNameCandidate(agent?.displayName, key);
    if (ownAgentName != null) {
      return ownAgentName;
    }

    final selfKey = selfMatrixUserId?.trim() ?? '';
    if (selfKey.isNotEmpty && selfKey == key) {
      final selfName = _normalizeDisplayNameCandidate(fallbackDisplayName, key);
      if (selfName != null) {
        return selfName;
      }
    }

    return key.localpart ?? key;
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
    if (getAgentByMatrixUserId(key) != null) {
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
      profileNotifier.value++;
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
        final localpart = key.localpart?.trim() ?? '';
        if (localpart.isNotEmpty) {
          _matrixLocalpartToAgent[localpart] = agent;
        }
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
    _profilePresentationByUserId.clear();
    _profileLookupInFlight.clear();
    _profileLookupLastAttemptAt.clear();
    _lastLoadedAt = null;
    _matrixLocalpartToAgent.clear();
    _repository.dispose();
    agentsNotifier.dispose();
    profileNotifier.dispose();
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
