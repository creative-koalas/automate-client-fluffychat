library;

import 'agent_template.dart';

class HireResult {
  final Future<UnifiedCreateAgentResponse> responseFuture;
  final String displayName;
  final String agentId;
  final String? avatarUrl;

  const HireResult({
    required this.responseFuture,
    required this.displayName,
    this.agentId = '',
    this.avatarUrl,
  });
}
