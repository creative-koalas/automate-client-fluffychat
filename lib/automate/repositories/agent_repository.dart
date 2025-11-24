/// Agent 数据仓库
/// 负责 Agent 相关的 API 调用和数据转换
library;

import '../core/api_client.dart';
import '../models/agent.dart';

/// Agent 数据仓库
class AgentRepository {
  final AutomateApiClient _apiClient;

  AgentRepository({AutomateApiClient? apiClient})
      : _apiClient = apiClient ?? AutomateApiClient();

  /// 获取当前用户的所有 Agent（支持游标分页）
  ///
  /// [cursor] 游标（首次请求传 null）
  /// [limit] 每页条数（默认 20）
  ///
  /// 返回 [AgentPage] 包含 agents 列表和分页信息
  Future<AgentPage> getUserAgents({int? cursor, int limit = 20}) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };
    if (cursor != null) {
      queryParams['cursor'] = cursor.toString();
    }

    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/agents/my-agents',
      queryParameters: queryParams,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    if (response.data == null) {
      return const AgentPage(agents: [], hasNextPage: false);
    }

    return AgentPage.fromJson(response.data!);
  }

  /// 获取 Agent 统计信息
  ///
  /// [agentId] Agent ID
  ///
  /// 返回 [AgentStats] 统计信息，如果获取失败返回 null（降级处理）
  Future<AgentStats?> getAgentStats(String agentId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/agents/$agentId/stats',
        fromJsonT: (data) => data as Map<String, dynamic>,
      );

      if (response.data == null) {
        return null;
      }

      return AgentStats.fromJson(response.data!);
    } catch (e) {
      // 统计信息获取失败不阻塞主流程
      return null;
    }
  }

  /// 删除 Agent
  ///
  /// [agentId] Agent ID
  /// [confirm] 确认删除（必须为 true）
  Future<void> deleteAgent(String agentId, {bool confirm = true}) async {
    await _apiClient.delete<void>(
      '/api/agents/$agentId',
      queryParameters: {'confirm': confirm.toString()},
    );
  }

  /// 释放资源
  void dispose() {
    _apiClient.dispose();
  }
}
