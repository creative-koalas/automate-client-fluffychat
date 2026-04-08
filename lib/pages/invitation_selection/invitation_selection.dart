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
  String currentSearchTerm = '';
  bool loading = false;
  List<InviteCandidate> foundCandidates = [];
  Set<String> memberIds = <String>{};
  Timer? coolDown;
  StreamSubscription? _roomStateSub;
  bool _inviteSuccessSnackBarVisible = false;
  int _searchRequestVersion = 0;

  String? get roomId => widget.roomId;

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
        .where(
          (r) => r.isDirectChat && (r.directChatMatrixID?.isNotEmpty ?? false),
        )
        .map(
          (r) => _buildCandidateFromUser(
            r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!),
          ),
        )
        .where(
          (candidate) => candidate.matrixUserId.trim().isNotEmpty,
        )
        .toList();
    contacts.sort(
      (a, b) => _candidateSortName(a).compareTo(
        _candidateSortName(b),
      ),
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

  InviteCandidate _buildCandidateFromUser(User user) {
    final matrixUserId = user.id.trim();
    final agent = _agentService.getAgentByMatrixUserId(matrixUserId);
    final fallbackDisplayName = user.displayName ?? user.calcDisplayname();
    return _decorateCandidate(
      InviteCandidate(
        kind: agent != null
            ? InviteCandidateKind.agent
            : InviteCandidateKind.matrix,
        matrixUserId: matrixUserId,
        displayName: fallbackDisplayName.trim().isNotEmpty
            ? fallbackDisplayName.trim()
            : (matrixUserId.localpart ?? matrixUserId),
        avatarUrl: user.avatarUrl,
        agentId: agent?.agentId,
        nickname: user.displayName?.trim(),
        isActive: agent?.isActive ?? true,
      ),
    );
  }

  InviteCandidate _buildCandidateFromAgent(Agent agent) {
    final matrixUserId = agent.matrixUserId?.trim() ?? '';
    return _decorateCandidate(
      InviteCandidate(
        kind: InviteCandidateKind.agent,
        matrixUserId: matrixUserId,
        displayName: agent.displayName.trim().isNotEmpty
            ? agent.displayName.trim()
            : (agent.agentId.trim().isNotEmpty
                ? agent.agentId.trim()
                : (matrixUserId.localpart ?? matrixUserId)),
        avatarUrl: _agentService.parseAvatarUri(agent.avatarUrl),
        agentId: agent.agentId.trim().isNotEmpty ? agent.agentId.trim() : null,
        nickname: agent.displayName.trim().isNotEmpty
            ? agent.displayName.trim()
            : null,
        isActive: agent.isActive,
      ),
    );
  }

  InviteCandidate _decorateCandidate(InviteCandidate candidate) {
    final matrixUserId = candidate.matrixUserId.trim();
    if (matrixUserId.isEmpty) {
      return candidate;
    }

    final agent = _agentService.getAgentByMatrixUserId(matrixUserId);
    final preferredDisplayName =
        _meaningfulDisplayLabel(candidate.nickname, matrixUserId) ??
            _meaningfulDisplayLabel(candidate.displayName, matrixUserId);
    final resolvedDisplayName = preferredDisplayName ??
        _agentService
            .resolveDisplayNameByMatrixUserId(
              matrixUserId,
              fallbackDisplayName: _preferNonEmpty(
                candidate.nickname,
                candidate.displayName,
              ),
            )
            .trim();
    final normalizedDisplayName = resolvedDisplayName.isNotEmpty
        ? resolvedDisplayName
        : (matrixUserId.localpart ?? matrixUserId);

    return candidate.copyWith(
      kind: agent != null ? InviteCandidateKind.agent : candidate.kind,
      displayName: normalizedDisplayName,
      avatarUrl: _agentService.resolveAvatarUriByMatrixUserId(
        matrixUserId,
        fallbackAvatarUri: candidate.avatarUrl,
      ),
      agentId: _preferNonEmpty(candidate.agentId, agent?.agentId),
      nickname: _preferNonEmpty(
        _meaningfulDisplayLabel(candidate.nickname, matrixUserId),
        _preferNonEmpty(
          _meaningfulDisplayLabel(candidate.displayName, matrixUserId),
          _meaningfulDisplayLabel(agent?.displayName, matrixUserId),
        ),
      ),
      isActive: candidate.isActive && (agent?.isActive ?? true),
    );
  }

  InviteCandidate _mergeCandidate(
    InviteCandidate primary,
    InviteCandidate secondary,
  ) {
    return _decorateCandidate(
      primary.copyWith(
        kind: primary.kind != InviteCandidateKind.matrix
            ? primary.kind
            : secondary.kind,
        displayName:
            _preferNonEmpty(primary.displayName, secondary.displayName),
        avatarUrl: primary.avatarUrl ?? secondary.avatarUrl,
        userId: _preferNonEmpty(primary.userId, secondary.userId),
        agentId: _preferNonEmpty(primary.agentId, secondary.agentId),
        nickname: _preferNonEmpty(primary.nickname, secondary.nickname),
        isActive: primary.isActive && secondary.isActive,
      ),
    );
  }

  String? _preferNonEmpty(String? primary, String? secondary) {
    final normalizedPrimary = primary?.trim();
    if (normalizedPrimary != null && normalizedPrimary.isNotEmpty) {
      return normalizedPrimary;
    }
    final normalizedSecondary = secondary?.trim();
    if (normalizedSecondary != null && normalizedSecondary.isNotEmpty) {
      return normalizedSecondary;
    }
    return null;
  }

  String? _meaningfulDisplayLabel(String? value, String matrixUserId) {
    final normalizedValue = value?.trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return null;
    }
    final localpart = matrixUserId.localpart?.trim();
    if (normalizedValue == matrixUserId ||
        (localpart != null &&
            localpart.isNotEmpty &&
            normalizedValue == localpart)) {
      return null;
    }
    return normalizedValue;
  }

  String _candidateSortName(InviteCandidate candidate) {
    final matrixUserId = candidate.matrixUserId.trim();
    final preferredName =
        _meaningfulDisplayLabel(candidate.nickname, matrixUserId) ??
            _meaningfulDisplayLabel(candidate.displayName, matrixUserId);
    return (preferredName ?? matrixUserId.localpart ?? matrixUserId)
        .trim()
        .toLowerCase();
  }

  List<InviteCandidate> _searchLocalCandidates(Client client, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <InviteCandidate>[];
    }

    final results = <InviteCandidate>[];
    final seen = <String>{};

    void addCandidate(InviteCandidate candidate) {
      final matrixUserId = candidate.matrixUserId.trim();
      if (matrixUserId.isEmpty ||
          seen.contains(matrixUserId) ||
          !_matchesCandidateQuery(candidate, normalizedQuery)) {
        return;
      }
      seen.add(matrixUserId);
      results.add(_decorateCandidate(candidate));
    }

    for (final room in client.rooms) {
      if (!room.isDirectChat ||
          (room.directChatMatrixID?.isNotEmpty ?? false) == false) {
        continue;
      }
      addCandidate(
        _buildCandidateFromUser(
          room.unsafeGetUserFromMemoryOrFallback(room.directChatMatrixID!),
        ),
      );
    }

    for (final agent in _agentService.agents) {
      if (!agent.isActive) {
        continue;
      }
      final candidate = _buildCandidateFromAgent(agent);
      if (candidate.matrixUserId.trim().isEmpty) {
        continue;
      }
      addCandidate(candidate);
    }

    results.sort(
      (a, b) => _compareCandidatesByQuery(
        normalizedQuery,
        a,
        b,
      ),
    );
    return results;
  }

  bool _matchesCandidateQuery(
    InviteCandidate candidate,
    String normalizedQuery,
  ) {
    final searchFields = <String>[
      candidate.displayName,
      candidate.nickname ?? '',
      candidate.agentId ?? '',
      candidate.userId ?? '',
      candidate.secondaryIdentifier,
      candidate.matrixUserId,
    ];

    return searchFields.any(
      (field) => field.trim().toLowerCase().contains(normalizedQuery),
    );
  }

  int _compareCandidatesByQuery(
    String normalizedQuery,
    InviteCandidate left,
    InviteCandidate right,
  ) {
    final leftRank = _candidateRank(normalizedQuery, left);
    final rightRank = _candidateRank(normalizedQuery, right);
    if (leftRank != rightRank) {
      return leftRank.compareTo(rightRank);
    }

    final leftName = _candidateSortName(left);
    final rightName = _candidateSortName(right);
    if (leftName != rightName) {
      return leftName.compareTo(rightName);
    }

    return left.matrixUserId.trim().toLowerCase().compareTo(
          right.matrixUserId.trim().toLowerCase(),
        );
  }

  int _candidateRank(String normalizedQuery, InviteCandidate candidate) {
    final primaryId =
        _preferNonEmpty(candidate.userId, candidate.agentId)?.toLowerCase() ??
            '';
    final displayName = candidate.displayName.trim().toLowerCase();
    final nickname = candidate.nickname?.trim().toLowerCase() ?? '';
    final matrixUserId = candidate.matrixUserId.trim().toLowerCase();

    switch (true) {
      case true when primaryId == normalizedQuery:
        return 0;
      case true
          when displayName == normalizedQuery || nickname == normalizedQuery:
        return 1;
      case true when matrixUserId == normalizedQuery:
        return 2;
      case true when primaryId.startsWith(normalizedQuery):
        return 3;
      case true
          when displayName.startsWith(normalizedQuery) ||
              nickname.startsWith(normalizedQuery):
        return 4;
      case true when matrixUserId.startsWith(normalizedQuery):
        return 5;
      case true when primaryId.contains(normalizedQuery):
        return 6;
      case true
          when displayName.contains(normalizedQuery) ||
              nickname.contains(normalizedQuery):
        return 7;
      case true when matrixUserId.contains(normalizedQuery):
        return 8;
      default:
        return 99;
    }
  }

  void inviteAction(BuildContext context, String id, String displayname) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId!)!;
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
    final isDismissedOwnedAgent = inviteTargetAgent?.isActive == false ||
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
    final normalizedText = text.trim();
    final requestVersion = ++_searchRequestVersion;
    currentSearchTerm = normalizedText;

    if (normalizedText.isEmpty) {
      if (!mounted) return;
      setState(() {
        foundCandidates = [];
        loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => loading = true);

    final client = Matrix.of(context).client;
    final localCandidates = _searchLocalCandidates(client, normalizedText);
    var backendCandidates = const <InviteCandidate>[];
    var matrixCandidates = const <InviteCandidate>[];
    Object? firstError;
    try {
      backendCandidates =
          await _inviteCandidateRepository.searchInviteCandidates(
        query: normalizedText,
        limit: 20,
      );
    } catch (e) {
      firstError ??= e;
    }
    try {
      matrixCandidates = await _searchMatrixCandidates(client, normalizedText);
    } catch (e) {
      firstError ??= e;
    }

    if (!mounted ||
        requestVersion != _searchRequestVersion ||
        currentSearchTerm != normalizedText) {
      return;
    }

    final mergedCandidates = _mergeCandidates(
      backendCandidates,
      localCandidates,
      matrixCandidates,
    ).toList(growable: true)
      ..sort(
        (left, right) => _compareCandidatesByQuery(normalizedText, left, right),
      );

    if (backendCandidates.isEmpty &&
        localCandidates.isEmpty &&
        matrixCandidates.isEmpty &&
        firstError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(firstError.toLocalizedString(context))),
      );
    }

    setState(() {
      foundCandidates = mergedCandidates;
      loading = false;
    });
  }

  Future<List<InviteCandidate>> _searchMatrixCandidates(
    Client client,
    String text,
  ) async {
    final response = await client.searchUserDirectory(text, limit: 10);
    final candidates = response.results
        .map(InviteCandidate.fromProfile)
        .map(_decorateCandidate)
        .toList(growable: true);
    if (text.isValidMatrixId &&
        candidates.every((candidate) => candidate.matrixUserId != text)) {
      candidates.add(
        _decorateCandidate(
          InviteCandidate.fromProfile(Profile.fromJson({'user_id': text})),
        ),
      );
    }
    return _filterRetiredOwnedAgentCandidates(client, candidates);
  }

  List<InviteCandidate> _filterRetiredOwnedAgentCandidates(
    Client client,
    List<InviteCandidate> candidates,
  ) {
    return candidates.where((candidate) {
      final cachedAgent = _agentService.getAgentByMatrixUserId(
        candidate.matrixUserId,
      );
      if (cachedAgent != null) {
        return cachedAgent.isActive;
      }
      if (_looksLikeOwnedAgentMatrixUserId(client, candidate.matrixUserId)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<InviteCandidate> _mergeCandidates(
    List<InviteCandidate> backendCandidates,
    List<InviteCandidate> localCandidates,
    List<InviteCandidate> matrixCandidates,
  ) {
    final merged = <String, InviteCandidate>{};

    void appendAll(List<InviteCandidate> items) {
      for (final item in items) {
        final normalizedItem = _decorateCandidate(item);
        final matrixUserId = normalizedItem.matrixUserId.trim();
        if (matrixUserId.isEmpty || !normalizedItem.isActive) {
          continue;
        }
        final existing = merged[matrixUserId];
        merged[matrixUserId] = existing == null
            ? normalizedItem
            : _mergeCandidate(existing, normalizedItem);
      }
    }

    appendAll(backendCandidates);
    appendAll(localCandidates);
    appendAll(matrixCandidates);
    return merged.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_agentService.refresh(forceRefresh: true));
    _refreshMemberIds();
    _roomStateSub = Matrix.of(context)
        .client
        .onSync
        .stream
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
    _searchRequestVersion++;
    coolDown?.cancel();
    controller.dispose();
    _roomStateSub?.cancel();
    _inviteCandidateRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InvitationSelectionView(this);
}
