library;

import 'agent_template.dart';

class HireResult {
  final Future<UnifiedCreateAgentResponse> responseFuture;
  final String displayName;

  const HireResult({
    required this.responseFuture,
    required this.displayName,
  });
}
