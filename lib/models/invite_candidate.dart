import 'package:matrix/matrix.dart';

enum InviteCandidateKind {
  user,
  agent,
  matrix,
}

class InviteCandidate {
  final InviteCandidateKind kind;
  final String matrixUserId;
  final String displayName;
  final Uri? avatarUrl;
  final String? userId;
  final String? agentId;
  final String? nickname;
  final bool isActive;

  const InviteCandidate({
    required this.kind,
    required this.matrixUserId,
    required this.displayName,
    this.avatarUrl,
    this.userId,
    this.agentId,
    this.nickname,
    this.isActive = true,
  });

  InviteCandidate copyWith({
    InviteCandidateKind? kind,
    String? matrixUserId,
    String? displayName,
    Uri? avatarUrl,
    bool clearAvatarUrl = false,
    String? userId,
    String? agentId,
    String? nickname,
    bool? isActive,
  }) {
    return InviteCandidate(
      kind: kind ?? this.kind,
      matrixUserId: matrixUserId ?? this.matrixUserId,
      displayName: displayName ?? this.displayName,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      userId: userId ?? this.userId,
      agentId: agentId ?? this.agentId,
      nickname: nickname ?? this.nickname,
      isActive: isActive ?? this.isActive,
    );
  }

  factory InviteCandidate.fromJson(Map<String, dynamic> json) {
    final rawKind = (json['kind'] as String? ?? '').trim().toLowerCase();
    final matrixUserId = (json['matrix_user_id'] as String? ?? '').trim();
    final displayName = (json['display_name'] as String? ?? '').trim();
    final nickname = (json['nickname'] as String?)?.trim();
    final rawAvatarUrl = (json['avatar_url'] as String? ?? '').trim();
    return InviteCandidate(
      kind: switch (rawKind) {
        'agent' => InviteCandidateKind.agent,
        'user' => InviteCandidateKind.user,
        _ => InviteCandidateKind.matrix,
      },
      matrixUserId: matrixUserId,
      displayName: displayName.isNotEmpty
          ? displayName
          : ((nickname?.isNotEmpty ?? false)
              ? nickname!
              : (matrixUserId.localpart ?? matrixUserId)),
      avatarUrl: rawAvatarUrl.isEmpty ? null : Uri.tryParse(rawAvatarUrl),
      userId: (json['user_id'] as String?)?.trim(),
      agentId: (json['agent_id'] as String?)?.trim(),
      nickname: nickname,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  factory InviteCandidate.fromProfile(Profile profile) {
    final matrixUserId = profile.userId.trim();
    final displayName = (profile.displayName ?? '').trim().isNotEmpty
        ? profile.displayName!.trim()
        : (matrixUserId.localpart ?? matrixUserId);
    return InviteCandidate(
      kind: InviteCandidateKind.matrix,
      matrixUserId: matrixUserId,
      displayName: displayName,
      avatarUrl: profile.avatarUrl,
      isActive: true,
    );
  }

  factory InviteCandidate.fromUser(User user) {
    return InviteCandidate(
      kind: InviteCandidateKind.matrix,
      matrixUserId: user.id,
      displayName: user.calcDisplayname(),
      avatarUrl: user.avatarUrl,
      isActive: true,
    );
  }

  String get secondaryIdentifier {
    switch (kind) {
      case InviteCandidateKind.agent:
        return (agentId?.isNotEmpty ?? false) ? agentId! : matrixUserId;
      case InviteCandidateKind.user:
        return (userId?.isNotEmpty ?? false) ? userId! : matrixUserId;
      case InviteCandidateKind.matrix:
        return matrixUserId;
    }
  }

  Profile toProfile() => Profile(
        userId: matrixUserId,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
}
