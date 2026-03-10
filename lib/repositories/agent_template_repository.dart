/// AgentTemplate 数据仓库
/// 负责 AgentTemplate 相关的 API 调用和数据转换
library;

import 'dart:math';

import '../core/api_client.dart';
import '../models/agent_template.dart';

// 导出 PluginConfig 供外部使用
export '../models/agent_template.dart' show PluginConfig;

/// AgentTemplate 数据仓库
class AgentTemplateRepository {
  final PsygoApiClient _apiClient;
  final Random _random = Random.secure();

  AgentTemplateRepository({
    PsygoApiClient? apiClient,
  }) : _apiClient = apiClient ?? PsygoApiClient();

  /// 获取激活的 Agent 模板列表
  ///
  /// 此 API 无需 JWT 鉴权，但需要发送 Accept-Language
  /// 后端会根据语言自动返回本地化的数据
  ///
  /// 返回 [AgentTemplate] 列表
  Future<List<AgentTemplate>> getActiveTemplates() async {
    final response = await _apiClient.get<List<dynamic>>(
      '/api/agent-templates/active',
      requiresAuth: false, // 公开端点，无需 JWT
      fromJsonT: (data) {
        // 后端返回 {"templates": [...]}，需要从中提取 templates 数组
        if (data is Map<String, dynamic>) {
          final templates = data['templates'];
          if (templates is List) {
            return templates;
          }
        }
        // 兼容直接返回数组的情况
        if (data is List) {
          return data;
        }
        return <dynamic>[];
      },
    );

    if (response.data == null || response.data!.isEmpty) {
      return [];
    }

    return response.data!
        .map((e) => AgentTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 从模板雇佣 Agent（调用统一创建接口）
  ///
  /// [templateId] 模板 ID
  /// [name] 员工名称（用户输入）
  /// [userRules] 额外规则/个性化描述（可选）
  /// [avatarUrl] 头像 URL（可选，通常从模板继承）
  ///
  /// 返回 [UnifiedCreateAgentAcceptedResponse]，包含 operationId 等信息
  Future<UnifiedCreateAgentAcceptedResponse> hireFromTemplate(
    int templateId,
    String name, {
    String? userRules,
    String? avatarUrl,
  }) async {
    return _submitCreateOperation(
      UnifiedCreateAgentRequest(
        name: name,
        templateId: templateId,
        userRules: userRules,
        avatarUrl: avatarUrl,
      ),
    );
  }

  /// 定制创建 Agent（无模板）
  ///
  /// [name] 员工名称
  /// [systemPrompt] 系统提示词（可选）
  ///
  /// 返回 [UnifiedCreateAgentAcceptedResponse]
  Future<UnifiedCreateAgentAcceptedResponse> createCustomAgent({
    required String name,
    String? systemPrompt,
  }) async {
    return _submitCreateOperation(
      UnifiedCreateAgentRequest(
        name: name,
        systemPrompt: systemPrompt,
        // 不指定 templateId，后端会创建空白 Agent
      ),
    );
  }

  /// 定制创建 Agent（带插件）
  ///
  /// [name] 员工名称
  /// [systemPrompt] 系统提示词（可选）
  /// [plugins] 插件配置列表（可选）
  /// [avatarUrl] 头像 URL（可选，DiceBear 等）
  ///
  /// 返回 [UnifiedCreateAgentAcceptedResponse]
  Future<UnifiedCreateAgentAcceptedResponse> createCustomAgentWithPlugins({
    required String name,
    String? systemPrompt,
    List<PluginConfig>? plugins,
    String? avatarUrl,
  }) async {
    return _submitCreateOperation(
      UnifiedCreateAgentRequest(
        name: name,
        systemPrompt: systemPrompt,
        plugins: plugins,
        avatarUrl: avatarUrl,
      ),
    );
  }

  Future<UnifiedCreateAgentAcceptedResponse> _submitCreateOperation(
    UnifiedCreateAgentRequest request,
  ) async {
    final accepted = await _apiClient.post<Map<String, dynamic>>(
      '/api/agents/create-unified',
      headers: {'Idempotency-Key': _newIdempotencyKey()},
      body: request.toJson(),
      fromJsonT: (data) =>
          data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
    final operation = UnifiedCreateAgentAcceptedResponse.fromJson(
      accepted.data ?? const <String, dynamic>{},
    );
    if (operation.operationId.trim().isEmpty) {
      throw ApiException(-1, 'Missing operation_id');
    }
    return operation;
  }

  String _newIdempotencyKey() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = _random.nextInt(1 << 32);
    return '$ts-$rand';
  }

  Future<UnifiedCreateAgentResponse> waitCreateOperation(
    String operationId,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 12));

    while (DateTime.now().isBefore(deadline)) {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/api/operations/$operationId',
        fromJsonT: (data) =>
            data is Map<String, dynamic> ? data : <String, dynamic>{},
      );

      final data = resp.data ?? <String, dynamic>{};
      final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
      if (status == 'succeeded') {
        final result = data['result'];
        if (result is Map<String, dynamic>) {
          return UnifiedCreateAgentResponse.fromJson(result);
        }
        throw ApiException(-1, 'Missing operation result');
      }
      if (status == 'failed') {
        final error = (data['error'] as String?)?.trim();
        throw ApiException(
          -1,
          error?.isNotEmpty == true ? error! : 'Operation failed',
        );
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    throw ApiException(-1, 'Operation timeout');
  }

  /// 释放资源
  void dispose() {
    _apiClient.dispose();
  }
}
