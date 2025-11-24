/// Plugin 数据模型
/// 对应后端 automate-assistant 的 Plugin 实体
/// 用于培训市场展示可安装的插件
library;

/// 插件领域模型
class Plugin {
  /// 插件 ID
  final int id;

  /// 插件名称（唯一标识）
  final String name;

  /// 插件描述
  final String description;

  /// 图标 URL
  final String iconUrl;

  /// 是否内置插件（内置插件不在前端展示）
  final bool isBuiltin;

  /// 安装数量（有多少员工已培训）
  final int installedCount;

  /// 配置表单 Schema（JSON Schema 格式）
  final Map<String, dynamic>? configSchema;

  /// 创建时间
  final String? createdAt;

  /// 更新时间
  final String? updatedAt;

  const Plugin({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    this.isBuiltin = false,
    required this.installedCount,
    this.configSchema,
    this.createdAt,
    this.updatedAt,
  });

  /// 从 JSON 创建 Plugin
  factory Plugin.fromJson(Map<String, dynamic> json) {
    return Plugin(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['icon_url'] as String? ?? '',
      isBuiltin: json['is_builtin'] as bool? ?? false,
      installedCount: json['installed_count'] as int? ?? 0,
      configSchema: json['config_schema'] as Map<String, dynamic>?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon_url': iconUrl,
      'is_builtin': isBuiltin,
      'installed_count': installedCount,
      'config_schema': configSchema,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 是否需要配置
  bool get requiresConfig => configSchema != null && configSchema!.isNotEmpty;

  /// 复制并修改
  Plugin copyWith({
    int? id,
    String? name,
    String? description,
    String? iconUrl,
    bool? isBuiltin,
    int? installedCount,
    Map<String, dynamic>? configSchema,
    String? createdAt,
    String? updatedAt,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      installedCount: installedCount ?? this.installedCount,
      configSchema: configSchema ?? this.configSchema,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plugin &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Plugin(name: $name, installedCount: $installedCount)';
}

/// Agent 已安装的插件
class AgentPlugin {
  /// 记录 ID
  final int id;

  /// Agent ID
  final String agentId;

  /// 插件名称
  final String pluginName;

  /// 状态：active / inactive / error / installing
  final String status;

  /// 配置（JSON）
  final Map<String, dynamic>? config;

  const AgentPlugin({
    required this.id,
    required this.agentId,
    required this.pluginName,
    required this.status,
    this.config,
  });

  /// 从 JSON 创建 AgentPlugin
  factory AgentPlugin.fromJson(Map<String, dynamic> json) {
    return AgentPlugin(
      id: json['id'] as int,
      agentId: json['agent_id'] as String,
      pluginName: json['plugin_name'] as String,
      status: json['status'] as String? ?? 'inactive',
      config: json['config'] as Map<String, dynamic>?,
    );
  }

  /// 是否已激活
  bool get isActive => status == 'active';

  /// 是否安装中
  bool get isInstalling => status == 'installing';

  /// 是否出错
  bool get hasError => status == 'error';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPlugin &&
          runtimeType == other.runtimeType &&
          agentId == other.agentId &&
          pluginName == other.pluginName;

  @override
  int get hashCode => Object.hash(agentId, pluginName);

  @override
  String toString() => 'AgentPlugin(agentId: $agentId, pluginName: $pluginName, status: $status)';
}

/// 安装插件请求
class InstallPluginRequest {
  final String agentId;
  final String pluginName;
  final Map<String, dynamic>? config;

  const InstallPluginRequest({
    required this.agentId,
    required this.pluginName,
    this.config,
  });

  Map<String, dynamic> toJson() {
    return {
      'agent_id': agentId,
      'plugin_name': pluginName,
      if (config != null) 'config': config,
    };
  }
}
