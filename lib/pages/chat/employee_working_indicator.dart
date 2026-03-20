import 'dart:async';

import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';
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
    final workingAgents = _getWorkingAgents();
    if (workingAgents.isEmpty) return const SizedBox.shrink();

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
                  (workingAgents.length - 1).clamp(0, 2) * overlapOffset,
              height: avatarSize,
              child: Stack(
                children: [
                  for (var i = workingAgents.length.clamp(0, 3) - 1;
                      i >= 0;
                      i--)
                    Positioned(
                      left: i * overlapOffset,
                      child: Avatar(
                        mxContent: _getAgentAvatarUri(workingAgents[i]),
                        name: workingAgents[i].displayName,
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
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: const _WorkingHintText(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Agent> _getWorkingAgents() {
    final directChatMatrixId = controller.room.directChatMatrixID;
    if (directChatMatrixId != null) {
      final directAgent =
          AgentService.instance.getAgentByMatrixUserId(directChatMatrixId);
      if (directAgent?.isWorking == true) {
        return [directAgent!];
      }
      return const [];
    }

    final roomMemberIds =
        controller.room.getParticipants().map((u) => u.id).toSet();
    return AgentService.instance.agents.where((a) {
      final matrixUserId = a.matrixUserId;
      if (matrixUserId == null || matrixUserId.isEmpty) {
        return false;
      }
      return roomMemberIds.contains(matrixUserId) && a.isWorking;
    }).toList();
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

class _WorkingHintText extends StatefulWidget {
  const _WorkingHintText();

  @override
  State<_WorkingHintText> createState() => _WorkingHintTextState();
}

enum _HintPhase { typing, holding, deleting }

class _WorkingHintTextState extends State<_WorkingHintText> {
  static const Duration _characterInterval = Duration(milliseconds: 85);
  static const Duration _holdDuration = Duration(milliseconds: 900);

  int _hintIndex = 0;
  int _visibleChars = 0;
  int _holdTick = 0;
  _HintPhase _phase = _HintPhase.typing;
  late final Timer _timer;

  int get _maxHoldTicks =>
      (_holdDuration.inMilliseconds / _characterInterval.inMilliseconds)
          .round();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_characterInterval, (_) => _onTick());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  List<String> _localizedHints() {
    final l10n = L10n.of(context);
    return <String>[
      l10n.employeeWorkingNotice1,
      l10n.employeeWorkingNotice2,
      l10n.employeeWorkingNotice3,
    ];
  }

  void _onTick() {
    if (!mounted) return;
    final hints = _localizedHints();
    if (hints.isEmpty) return;
    final current = hints[_hintIndex % hints.length];
    final maxChars = current.length;

    setState(() {
      if (_visibleChars > maxChars) {
        _visibleChars = maxChars;
      }

      switch (_phase) {
        case _HintPhase.typing:
          if (_visibleChars < maxChars) {
            _visibleChars += 1;
          } else {
            _phase = _HintPhase.holding;
            _holdTick = 0;
          }
          break;
        case _HintPhase.holding:
          if (_holdTick < _maxHoldTicks) {
            _holdTick += 1;
          } else {
            _phase = _HintPhase.deleting;
          }
          break;
        case _HintPhase.deleting:
          if (_visibleChars > 0) {
            _visibleChars -= 1;
          } else {
            _hintIndex = (_hintIndex + 1) % hints.length;
            _phase = _HintPhase.typing;
          }
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hints = _localizedHints();
    final current = hints[_hintIndex % hints.length];
    final safeLength = _visibleChars.clamp(0, current.length);
    final visibleText = current.substring(0, safeLength);

    return Text(
      visibleText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
