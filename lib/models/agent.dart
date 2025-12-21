/// Agent 数据模型
/// 对应后端 automate-assistant 的 Agent 实体
library;

/// Agent 领域模型
class Agent {
  /// Agent 唯一标识（如 "agent_1_abc123"）
  final String agentId;

  /// 用户友好显示名称（用于 UI 展示，如 "Alice"）
  final String displayName;

  /// 系统内部名称（符合 K8s DNS-1035 规范，如 "alice" 或 "alice-abc123"）
  final String name;

  /// Agent 描述
  final String? description;

  /// 头像 URL
  final String? avatarUrl;

  /// 是否激活
  final bool isActive;

  /// Pod 就绪状态（插件恢复完成后为 true）
  /// 前端逻辑：isReady=false 时显示"入职中"，阻止用户交互
  final bool isReady;

  /// Agent 的 Matrix 账号 ID（如 @agent-1-abc:matrix.org）
  final String? matrixUserId;

  /// 创建时间（ISO 8601 格式）
  final String createdAt;

  /// 合同到期时间（ISO 8601 格式）
  final String? contractExpiresAt;

  /// 工作状态：working（工作中）/ idle_long（摸鱼中）/ idle（睡觉中）
  final String workStatus;

  /// 最后活跃时间（ISO 8601 格式）
  final String? lastActiveAt;

  const Agent({
    required this.agentId,
    required this.displayName,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.isActive,
    required this.isReady,
    this.matrixUserId,
    required this.createdAt,
    this.contractExpiresAt,
    this.workStatus = 'idle_long',
    this.lastActiveAt,
  });

  /// 从 JSON 创建 Agent
  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      agentId: json['agent_id'] as String,
      displayName: json['display_name'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      isReady: json['is_ready'] as bool? ?? false,
      matrixUserId: json['matrix_user_id'] as String?,
      createdAt: json['created_at'] as String,
      contractExpiresAt: json['contract_expires_at'] as String?,
      workStatus: json['work_status'] as String? ?? 'idle_long',
      lastActiveAt: json['last_active_at'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'agent_id': agentId,
      'display_name': displayName,
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'is_active': isActive,
      'is_ready': isReady,
      'matrix_user_id': matrixUserId,
      'created_at': createdAt,
      'contract_expires_at': contractExpiresAt,
      'work_status': workStatus,
      'last_active_at': lastActiveAt,
    };
  }

  /// 复制并修改
  Agent copyWith({
    String? agentId,
    String? displayName,
    String? name,
    String? description,
    String? avatarUrl,
    bool? isActive,
    bool? isReady,
    String? matrixUserId,
    String? createdAt,
    String? contractExpiresAt,
    String? workStatus,
    String? lastActiveAt,
  }) {
    return Agent(
      agentId: agentId ?? this.agentId,
      displayName: displayName ?? this.displayName,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isActive: isActive ?? this.isActive,
      isReady: isReady ?? this.isReady,
      matrixUserId: matrixUserId ?? this.matrixUserId,
      createdAt: createdAt ?? this.createdAt,
      contractExpiresAt: contractExpiresAt ?? this.contractExpiresAt,
      workStatus: workStatus ?? this.workStatus,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  /// 获取实际工作状态
  /// 规则：
  /// - 后端返回 working（有 is_active=1 的任务）→ 直接使用
  /// - 后端返回非 working 时，根据 lastActiveAt 细分：
  ///   - 0 < 最后活跃时间 < 5分钟：摸鱼中 (idle)
  ///   - 最后活跃时间 > 5分钟：睡觉中 (idle_long)
  String get computedWorkStatus {
    // 后端已计算好 working 状态（有 is_active=1 的任务），直接使用
    if (workStatus == 'working') {
      return 'working';
    }

    // 非 working 状态，根据 lastActiveAt 细分 idle/idle_long
    if (lastActiveAt == null) {
      return 'idle_long'; // 没有活跃记录，默认睡觉中
    }

    try {
      final lastActive = DateTime.parse(lastActiveAt!);
      final now = DateTime.now();
      final difference = now.difference(lastActive);

      if (difference.inMinutes < 5) {
        return 'idle'; // 摸鱼中
      } else {
        return 'idle_long'; // 睡觉中
      }
    } catch (_) {
      return 'idle_long'; // 解析失败，默认睡觉中
    }
  }

  /// 是否正在工作（基于计算的状态）
  bool get isWorking => computedWorkStatus == 'working';

  /// 是否长时间空闲（基于计算的状态）
  bool get isIdleLong => computedWorkStatus == 'idle_long';

  /// 获取工作状态显示文本的 key（基于计算的状态）
  String get workStatusKey {
    switch (computedWorkStatus) {
      case 'working':
        return 'employee_working';
      case 'idle_long':
        return 'employee_idle_long';
      default:
        return 'employee_idle';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Agent &&
          runtimeType == other.runtimeType &&
          agentId == other.agentId;

  @override
  int get hashCode => agentId.hashCode;

  @override
  String toString() => 'Agent(agentId: $agentId, displayName: $displayName)';
}

/// Agent 统计信息
class AgentStats {
  final String agentId;
  final int totalTasks;
  final int completedTasks;
  final int activeTasks;
  final int totalPlugins;
  final int activePlugins;
  final double workHours;
  final String lastActiveAt;
  final String createdAt;

  const AgentStats({
    required this.agentId,
    required this.totalTasks,
    required this.completedTasks,
    required this.activeTasks,
    required this.totalPlugins,
    required this.activePlugins,
    required this.workHours,
    required this.lastActiveAt,
    required this.createdAt,
  });

  factory AgentStats.fromJson(Map<String, dynamic> json) {
    return AgentStats(
      agentId: json['agent_id'] as String,
      totalTasks: json['total_tasks'] as int? ?? 0,
      completedTasks: json['completed_tasks'] as int? ?? 0,
      activeTasks: json['active_tasks'] as int? ?? 0,
      totalPlugins: json['total_plugins'] as int? ?? 0,
      activePlugins: json['active_plugins'] as int? ?? 0,
      workHours: (json['work_hours'] as num?)?.toDouble() ?? 0.0,
      lastActiveAt: json['last_active_at'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// Agent 分页结果
class AgentPage {
  final List<Agent> agents;
  final int? nextCursor;
  final bool hasNextPage;

  const AgentPage({
    required this.agents,
    this.nextCursor,
    required this.hasNextPage,
  });

  factory AgentPage.fromJson(Map<String, dynamic> json) {
    final agentsJson = json['agents'] as List<dynamic>? ?? [];
    return AgentPage(
      agents: agentsJson.map((e) => Agent.fromJson(e as Map<String, dynamic>)).toList(),
      nextCursor: json['next_cursor'] as int?,
      hasNextPage: json['has_next_page'] as bool? ?? false,
    );
  }
}
