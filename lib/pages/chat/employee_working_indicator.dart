import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/models/agent.dart';
import 'package:psygo/pages/chat/chat.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/widgets/avatar.dart';

class EmployeeWorkingIndicator extends StatelessWidget {
  final ChatController controller;

  const EmployeeWorkingIndicator(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingIds = controller.waitingForReplyEmployeeIds;
    if (waitingIds.isEmpty) return const SizedBox.shrink();
    final waitingAgents = _getWaitingAgents(waitingIds);
    if (waitingAgents.isEmpty) return const SizedBox.shrink();

    const avatarSize = 28.0;
    const overlapOffset = 16.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: avatarSize +
                  (waitingAgents.length - 1).clamp(0, 2) * overlapOffset,
              height: avatarSize,
              child: Stack(
                children: [
                  for (var i = waitingAgents.length.clamp(0, 3) - 1;
                      i >= 0;
                      i--)
                    Positioned(
                      left: i * overlapOffset,
                      child: Avatar(
                        mxContent: _getAgentAvatarUri(waitingAgents[i]),
                        name: waitingAgents[i].displayName,
                        size: avatarSize,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withAlpha(30),
                    width: 1,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: const _TypingDots(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Agent> _getWaitingAgents(Set<String> waitingIds) {
    return AgentService.instance.agents
        .where((a) =>
            a.matrixUserId != null &&
            waitingIds.contains(a.matrixUserId),)
        .toList();
  }

  Uri? _getAgentAvatarUri(Agent agent) {
    if (agent.avatarUrl != null && agent.avatarUrl!.isNotEmpty) {
      final uri = AgentService.instance.parseAvatarUri(agent.avatarUrl);
      if (uri != null) return uri;
    }
    if (agent.matrixUserId != null) {
      return AgentService.instance.getAgentAvatarUri(agent.matrixUserId!);
    }
    return null;
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  int _tick = 0;

  late final Timer _timer;

  static const Duration animationDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    _timer = Timer.periodic(
      animationDuration,
      (_) {
        if (!mounted) return;
        setState(() {
          _tick = (_tick + 1) % 4;
        });
      },
    );
    super.initState();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 8.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          AnimatedContainer(
            duration: animationDuration * 1.5,
            curve: FluffyThemes.curveStandard,
            width: size,
            height: _tick == i ? size * 2 : size,
            margin: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: _tick == i ? 4 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 2),
              color: theme.colorScheme.secondary,
            ),
          ),
      ],
    );
  }
}
