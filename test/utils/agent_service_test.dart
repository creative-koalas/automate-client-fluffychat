import 'package:flutter_test/flutter_test.dart';

import 'package:psygo/models/agent.dart';
import 'package:psygo/services/agent_service.dart';

void main() {
  final agentService = AgentService.instance;

  test('renders own agent display name', () {
    const matrixUserId = '@agent-1-owned:matrix.org';
    agentService.updateAgent(
      const Agent(
        agentId: 'agent_1_owned',
        displayName: 'Owned Bot',
        name: 'owned-bot',
        isActive: true,
        isReady: true,
        matrixUserId: matrixUserId,
        createdAt: '2026-03-24T00:00:00Z',
      ),
    );

    expect(
      agentService.resolveDisplayNameByMatrixUserId(
        matrixUserId,
        fallbackDisplayName: 'Fallback Name',
      ),
      'Owned Bot',
    );
  });

  test('keeps human display name fallback for non-agent accounts', () {
    expect(
      agentService.resolveDisplayNameByMatrixUserId(
        '@alice:matrix.org',
        fallbackDisplayName: 'Alice',
      ),
      'Alice',
    );
  });

  test('does not render alias for external bot-like accounts', () {
    const matrixUserId = '@agent-9-other:matrix.org';

    expect(
      agentService.tryResolveDisplayNameByMatrixUserId(
        matrixUserId,
        fallbackDisplayName: 'Other Bot Alias',
      ),
      isNull,
    );
    expect(
      agentService.resolveDisplayNameByMatrixUserId(
        matrixUserId,
        fallbackDisplayName: 'Other Bot Alias',
      ),
      'agent-9-other',
    );
  });
}
