import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/models/agent.dart';
import 'package:psygo/models/invite_candidate.dart';
import 'package:psygo/pages/invitation_selection/invitation_selection_view.dart';
import 'package:psygo/repositories/invite_candidate_repository.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/matrix.dart';
import '../../utils/localized_exception_extension.dart';

class InvitationSelection extends StatefulWidget {
  final String roomId;
  const InvitationSelection({super.key, required this.roomId});

  @override
  InvitationSelectionController createState() =>
      InvitationSelectionController();
}

class InvitationSelectionController extends State<InvitationSelection> {
  final AgentService _agentService = AgentService.instance;
  final InviteCandidateRepository _inviteCandidateRepository =
      InviteCandidateRepository();
  TextEditingController controller = TextEditingController();
  late String currentSearchTerm;
  bool loading = false;
  List<InviteCandidate> foundCandidates = [];
  Set<String> memberIds = <String>{};
  Timer? coolDown;
  StreamSubscription? _roomStateSub;
  bool _inviteSuccessSnackBarVisible = false;

  String? get roomId => widget.roomId;

  void _onAgentPresentationChanged() {
    if (!mounted) return;
    final client = Matrix.of(context).client;
    setState(() {
      if (foundCandidates.isNotEmpty) {
        foundCandidates = foundCandidates
            .map((candidate) => _hydrateInviteCandidate(client, candidate))
            .toList(growable: false);
      }
    });
  }

  Future<void> _refreshMemberIds() async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    if (room == null) return;

    try {
      final participants = await room.requestParticipants(
        [...Membership.values]..remove(Membership.leave),
      );
      if (!mounted) return;
      setState(() {
        memberIds = participants.map((u) => u.id).toSet();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        memberIds = room.getParticipants().map((u) => u.id).toSet();
      });
    }
  }

  bool _isAlreadyInRoomError(Object error) {
    if (error is! MatrixException) return false;
    final message = error.errorMessage.toLowerCase();
    return message.contains('already in the room') ||
        message.contains('already joined') ||
        message.contains('already a member') ||
        message.contains('is in room') ||
        message.contains('already invited') ||
        message.contains('已在') ||
        message.contains('已经在');
  }

  Future<List<InviteCandidate>> getContacts(BuildContext context) async {
    final client = Matrix.of(context).client;
    final contacts = client.rooms
        .where((r) => r.isDirectChat)
        .map(
          (r) => _hydrateInviteCandidate(
            client,
            InviteCandidate.fromUser(
              r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!),
            ),
          ),
        )
        .toList();
    contacts.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return contacts;
  }

  void _showInviteSuccessSnackBar(BuildContext context, String message) {
    if (_inviteSuccessSnackBarVisible) return;
    final messenger = ScaffoldMessenger.of(context);
    _inviteSuccessSnackBarVisible = true;
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: InkWell(
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        ),
      ),
    );
    controller.closed.whenComplete(() {
      _inviteSuccessSnackBarVisible = false;
    });
  }

  bool _looksLikeOwnedAgentMatrixUserId(Client client, String matrixUserId) {
    final normalizedUserId = matrixUserId.trim();
    if (normalizedUserId.isEmpty) {
      return false;
    }

    final targetDomain = normalizedUserId.domain?.trim().toLowerCase();
    final currentDomain = client.userID?.domain?.trim().toLowerCase();
    if (targetDomain == null ||
        currentDomain == null ||
        targetDomain != currentDomain) {
      return false;
    }

    final localpart = normalizedUserId.localpart?.trim().toLowerCase() ?? '';
    return localpart.startsWith('agent') ||
        localpart.contains('agent-') ||
        localpart.contains('agent_');
  }

  Future<Agent?> _resolveInviteTargetAgent(
    Client client,
    String matrixUserId,
  ) async {
    final cached = _agentService.getAgentByMatrixUserId(matrixUserId);
    if (cached != null) {
      return cached;
    }

    if (!_looksLikeOwnedAgentMatrixUserId(client, matrixUserId)) {
      return null;
    }

    await _agentService.refresh(forceRefresh: true);
    return _agentService.getAgentByMatrixUserId(matrixUserId);
  }

  String _resolveInviteTargetDisplayName({
    required String matrixUserId,
    required String fallbackDisplayName,
    Agent? inviteTargetAgent,
  }) {
    final agentDisplayName = inviteTargetAgent?.displayName.trim() ?? '';
    if (agentDisplayName.isNotEmpty) {
      return agentDisplayName;
    }

    final resolved = _agentService
        .resolveDisplayNameByMatrixUserId(
          matrixUserId,
          fallbackDisplayName: fallbackDisplayName,
        )
        .trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }

    return matrixUserId.localpart ?? fallbackDisplayName;
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  InviteCandidate _hydrateInviteCandidate(
    Client client,
    InviteCandidate candidate,
  ) {
    final matrixUserId = candidate.matrixUserId.trim();
    if (matrixUserId.isEmpty) {
      return candidate;
    }

    _agentService.ensureMatrixProfilePresentationById(
      client: client,
      matrixUserId: matrixUserId,
      fallbackDisplayName:
          _trimToNull(candidate.nickname) ?? candidate.displayName,
      fallbackAvatarUri: candidate.avatarUrl,
    );

    final agent = _agentService.getAgentByMatrixUserId(matrixUserId);
    final fallbackDisplayName =
        _trimToNull(candidate.nickname) ?? candidate.displayName;
    final resolvedDisplayName = _agentService.resolveDisplayNameByMatrixUserId(
      matrixUserId,
      fallbackDisplayName: fallbackDisplayName,
    );
    final resolvedAvatarUrl = _agentService.resolveAvatarUriByMatrixUserId(
      matrixUserId,
      fallbackAvatarUri: candidate.avatarUrl,
    );

    return InviteCandidate(
      kind: agent == null ? candidate.kind : InviteCandidateKind.agent,
      matrixUserId: matrixUserId,
      displayName: resolvedDisplayName,
      avatarUrl: resolvedAvatarUrl,
      userId: candidate.userId,
      agentId: _trimToNull(agent?.agentId) ?? _trimToNull(candidate.agentId),
      nickname:
          _trimToNull(agent?.displayName) ?? _trimToNull(candidate.nickname),
      isActive: agent?.isActive ?? candidate.isActive,
    );
  }

  void inviteAction(BuildContext context, InviteCandidate candidate) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId!)!;
    final id = candidate.matrixUserId;
    final displayname = candidate.displayName;
    if (!room.canInvite) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noPermission)));
      return;
    }
    if (memberIds.contains(id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.userAlreadyInGroup)));
      return;
    }

    final inviteTargetAgent = await _resolveInviteTargetAgent(client, id);
    final isOwnedAgent = inviteTargetAgent?.isActive == true;
    final isDismissedOwnedAgent =
        inviteTargetAgent?.isActive == false ||
        (inviteTargetAgent == null &&
            _looksLikeOwnedAgentMatrixUserId(client, id));
    final resolvedDisplayName = _resolveInviteTargetDisplayName(
      matrixUserId: id,
      fallbackDisplayName: displayname,
      inviteTargetAgent: inviteTargetAgent,
    );

    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        if (isDismissedOwnedAgent) {
          throw l10n.userLeftTheChat(resolvedDisplayName);
        }
        try {
          await room.invite(id);
        } on MatrixException catch (e) {
          if (_isAlreadyInRoomError(e)) {
            throw l10n.userAlreadyInGroup;
          }
          if (isOwnedAgent) {
            throw l10n.tryAgain;
          }
          rethrow;
        }
      },
    );
    if (success.error == null) {
      setState(() {
        memberIds = {...memberIds, id};
      });
      _showInviteSuccessSnackBar(
        context,
        isOwnedAgent
            ? l10n.youInvitedUser(resolvedDisplayName)
            : l10n.contactHasBeenInvitedToTheGroup,
      );
    }
  }

  void searchUserWithCoolDown(String text) async {
    coolDown?.cancel();
    coolDown = Timer(
      const Duration(milliseconds: 500),
      () => searchUser(context, text),
    );
  }

  void searchUser(BuildContext context, String text) async {
    coolDown?.cancel();
    if (text.isEmpty) {
      setState(() {
        foundCandidates = [];
        loading = false;
      });
      currentSearchTerm = '';
      return;
    }
    currentSearchTerm = text.trim();
    if (currentSearchTerm.isEmpty) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    final client = Matrix.of(context).client;
    var backendCandidates = const <InviteCandidate>[];
    var localCandidates = const <InviteCandidate>[];
    var matrixCandidates = const <InviteCandidate>[];
    Object? firstError;
    localCandidates = await _searchLocalCandidates(currentSearchTerm);
    try {
      backendCandidates = await _inviteCandidateRepository
          .searchInviteCandidates(query: currentSearchTerm, limit: 20);
      backendCandidates = backendCandidates
          .map((candidate) => _hydrateInviteCandidate(client, candidate))
          .toList(growable: false);
    } catch (e) {
      firstError ??= e;
    }
    try {
      matrixCandidates = await _searchMatrixCandidates(
        client,
        currentSearchTerm,
      );
    } catch (e) {
      firstError ??= e;
    }

    if (!mounted || currentSearchTerm != text.trim()) {
      return;
    }

    final mergedCandidates = _mergeCandidates(
      _mergeCandidates(backendCandidates, localCandidates),
      matrixCandidates,
    );

    if (mergedCandidates.isEmpty && firstError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(firstError.toLocalizedString(context))),
      );
    }

    setState(() {
      foundCandidates = mergedCandidates;
      loading = false;
    });
  }

  Future<List<InviteCandidate>> _searchLocalCandidates(String text) async {
    final normalizedQuery = text.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <InviteCandidate>[];
    }

    final client = Matrix.of(context).client;
    final contacts = await getContacts(context);
    return _filterRetiredOwnedAgentCandidates(
      client,
      contacts
          .where((candidate) {
            final displayName = candidate.displayName.trim().toLowerCase();
            final matrixUserId = candidate.matrixUserId.trim().toLowerCase();
            final secondaryIdentifier = candidate.secondaryIdentifier
                .trim()
                .toLowerCase();
            final nickname = candidate.nickname?.trim().toLowerCase() ?? '';

            return displayName.contains(normalizedQuery) ||
                matrixUserId.contains(normalizedQuery) ||
                secondaryIdentifier.contains(normalizedQuery) ||
                nickname.contains(normalizedQuery);
          })
          .toList(growable: false),
    );
  }

  Future<List<InviteCandidate>> _searchMatrixCandidates(
    Client client,
    String text,
  ) async {
    final response = await client.searchUserDirectory(text, limit: 10);
    final candidates = response.results
        .map(InviteCandidate.fromProfile)
        .toList(growable: true);
    if (text.isValidMatrixId &&
        candidates.every((candidate) => candidate.matrixUserId != text)) {
      candidates.add(
        InviteCandidate.fromProfile(Profile.fromJson({'user_id': text})),
      );
    }
    return _filterRetiredOwnedAgentCandidates(
      client,
      candidates
          .map((candidate) => _hydrateInviteCandidate(client, candidate))
          .toList(growable: false),
    );
  }

  List<InviteCandidate> _filterRetiredOwnedAgentCandidates(
    Client client,
    List<InviteCandidate> candidates,
  ) {
    return candidates
        .where((candidate) {
          final cachedAgent = _agentService.getAgentByMatrixUserId(
            candidate.matrixUserId,
          );
          if (cachedAgent != null) {
            return cachedAgent.isActive;
          }
          if (_looksLikeOwnedAgentMatrixUserId(
            client,
            candidate.matrixUserId,
          )) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<InviteCandidate> _mergeCandidates(
    List<InviteCandidate> backendCandidates,
    List<InviteCandidate> matrixCandidates,
  ) {
    final merged = <InviteCandidate>[];
    final seen = <String>{};

    void appendAll(List<InviteCandidate> items) {
      for (final item in items) {
        final matrixUserId = item.matrixUserId.trim();
        if (matrixUserId.isEmpty || seen.contains(matrixUserId)) {
          continue;
        }
        seen.add(matrixUserId);
        merged.add(item);
      }
    }

    appendAll(backendCandidates);
    appendAll(matrixCandidates);
    return merged;
  }

  @override
  void initState() {
    super.initState();
    currentSearchTerm = '';
    _agentService.agentsNotifier.addListener(_onAgentPresentationChanged);
    _agentService.profileNotifier.addListener(_onAgentPresentationChanged);
    unawaited(_agentService.refresh(forceRefresh: true));
    _refreshMemberIds();
    _roomStateSub = Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[roomId]?.timeline?.events?.any(
                (event) => event.type == EventTypes.RoomMember,
              ) ??
              false,
        )
        .listen((_) => _refreshMemberIds());
  }

  @override
  void dispose() {
    coolDown?.cancel();
    controller.dispose();
    _roomStateSub?.cancel();
    _agentService.agentsNotifier.removeListener(_onAgentPresentationChanged);
    _agentService.profileNotifier.removeListener(_onAgentPresentationChanged);
    _inviteCandidateRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InvitationSelectionView(this);
}
