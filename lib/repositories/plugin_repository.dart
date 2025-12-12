/// Plugin 数据仓库
/// 负责 Plugin 相关的 API 调用和数据转换
library;

import '../core/api_client.dart';
import '../models/plugin.dart';

/// Plugin 数据仓库
class PluginRepository {
  final PsygoApiClient _apiClient;

  PluginRepository({PsygoApiClient? apiClient})
      : _apiClient = apiClient ?? PsygoApiClient();

  /// 获取所有插件列表（带用户安装统计）
  ///
  /// 返回 [Plugin] 列表，自动过滤掉 isBuiltin=true 的内置插件
  Future<List<Plugin>> getPluginsWithStats() async {
    final response = await _apiClient.get<List<dynamic>>(
      '/plugins/stats',
      fromJsonT: (data) {
        // data 可能是 List 或空对象
        if (data is List) {
          return data;
        }
        return <dynamic>[];
      },
    );

    if (response.data == null || response.data!.isEmpty) {
      return [];
    }

    // 解析并过滤内置插件
    return response.data!
        .map((e) => Plugin.fromJson(e as Map<String, dynamic>))
        .where((plugin) => !plugin.isBuiltin)
        .toList();
  }

  /// 获取 Agent 已安装的插件列表
  ///
  /// [agentId] Agent ID
  ///
  /// 返回 [AgentPlugin] 列表
  Future<List<AgentPlugin>> getAgentPlugins(String agentId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/plugins/agent/$agentId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    if (response.data == null) {
      return [];
    }

    final pluginsJson = response.data!['plugins'] as List<dynamic>? ?? [];
    return pluginsJson
        .map((e) => AgentPlugin.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 为 Agent 安装插件
  ///
  /// [agentId] Agent ID
  /// [pluginName] 插件名称
  /// [config] 配置（可选）
  ///
  /// 返回安装后的 [AgentPlugin]
  Future<AgentPlugin> installPlugin(
    String agentId,
    String pluginName, {
    Map<String, dynamic>? config,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/plugins/install',
      body: InstallPluginRequest(
        agentId: agentId,
        pluginName: pluginName,
        config: config,
      ).toJson(),
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    // 从响应中提取 agent_plugin
    final agentPluginJson = response.data?['agent_plugin'] as Map<String, dynamic>?;
    if (agentPluginJson == null) {
      // 如果响应格式不符预期，构造一个基本的 AgentPlugin
      return AgentPlugin(
        id: 0,
        agentId: agentId,
        pluginName: pluginName,
        status: 'installing',
      );
    }

    return AgentPlugin.fromJson(agentPluginJson);
  }

  /// 卸载插件
  ///
  /// [agentId] Agent ID
  /// [pluginName] 插件名称
  Future<void> uninstallPlugin(String agentId, String pluginName) async {
    await _apiClient.delete<void>(
      '/plugins/uninstall',
      queryParameters: {
        'agent_id': agentId,
        'plugin_name': pluginName,
      },
    );
  }

  /// 释放资源
  void dispose() {
    _apiClient.dispose();
  }
}
