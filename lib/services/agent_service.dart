/// Agent 服务（单例）
/// 提供员工列表缓存和查询功能
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

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
  Future<void> _loadAllAgents() async {
    final allAgents = <Agent>[];
    int? cursor;
    var hasMore = true;

    while (hasMore) {
      final page = await _repository.getUserAgents(cursor: cursor, limit: 50);
      allAgents.addAll(page.agents);
      cursor = page.nextCursor;
      hasMore = page.hasNextPage;
    }

    _agents = allAgents;
    _rebuildMatrixUserIdMap();
    agentsNotifier.value = List.unmodifiable(_agents);
    debugPrint('[AgentService] Loaded ${_agents.length} agents');
  }

  /// 重建 Matrix User ID -> Agent 映射
  void _rebuildMatrixUserIdMap() {
    _matrixUserIdToAgent.clear();
    for (final agent in _agents) {
      if (agent.matrixUserId != null && agent.matrixUserId!.isNotEmpty) {
        _matrixUserIdToAgent[agent.matrixUserId!] = agent;
      }
    }
  }

  /// 刷新员工列表
  Future<void> refresh() async {
    if (_isLoading) return;

    _isLoading = true;
    try {
      await _loadAllAgents();
    } catch (e) {
      debugPrint('[AgentService] Refresh failed: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// 根据 Matrix User ID 查找员工
  /// 返回 null 表示不是员工
  Agent? getAgentByMatrixUserId(String? matrixUserId) {
    if (matrixUserId == null || matrixUserId.isEmpty) return null;
    return _matrixUserIdToAgent[matrixUserId];
  }

  /// 检查 Matrix User ID 是否是员工
  bool isEmployee(String? matrixUserId) {
    return getAgentByMatrixUserId(matrixUserId) != null;
  }

  /// 安全地获取员工头像 URI
  /// 返回 null 如果不是员工、没有头像或头像 URL 无效
  Uri? getAgentAvatarUri(String? matrixUserId) {
    final agent = getAgentByMatrixUserId(matrixUserId);
    if (agent?.avatarUrl == null || agent!.avatarUrl!.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(agent.avatarUrl!);
    // 验证 URI 是否有效（必须有 scheme 和 host）
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return uri;
    }
    return null;
  }

  /// 获取员工头像和显示名称（用于 Avatar 组件）
  /// 返回 (avatarUri, displayName)，如果不是员工或头像无效则返回 (null, null)
  (Uri?, String?) getAgentAvatarAndName(String? matrixUserId) {
    final agent = getAgentByMatrixUserId(matrixUserId);
    if (agent == null) return (null, null);

    final avatarUri = getAgentAvatarUri(matrixUserId);
    return (avatarUri, agent.displayName);
  }

  /// 更新单个员工信息（用于局部更新）
  void updateAgent(Agent agent) {
    final index = _agents.indexWhere((a) => a.agentId == agent.agentId);
    if (index != -1) {
      _agents[index] = agent;
      if (agent.matrixUserId != null && agent.matrixUserId!.isNotEmpty) {
        _matrixUserIdToAgent[agent.matrixUserId!] = agent;
      }
      agentsNotifier.value = List.unmodifiable(_agents);
    }
  }

  /// 释放资源
  void dispose() {
    _repository.dispose();
    agentsNotifier.dispose();
  }
}
