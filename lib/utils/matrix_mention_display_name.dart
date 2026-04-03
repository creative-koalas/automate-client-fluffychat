import 'package:matrix/matrix.dart';
import 'package:psygo/services/agent_service.dart';

final RegExp _matrixMentionPattern = RegExp(
  r'(^|[\s\(\[\{<，。！？、；：])(@[A-Za-z0-9._=+\-/]+:[A-Za-z0-9.-]+(?::\d+)?)(?=$|[\s\)\]\}>，。！？、；：,.!?])',
  multiLine: true,
);

String renderMatrixMentionsWithDisplayName({
  required String text,
  required Room room,
}) {
  if (text.isEmpty || !text.contains('@') || !text.contains(':')) {
    return text;
  }

  return text.replaceAllMapped(_matrixMentionPattern, (match) {
    final matrixUserId = match.group(2);
    if (matrixUserId == null || matrixUserId.isEmpty) {
      return match.group(0) ?? '';
    }

    final displayName = resolveMatrixMentionDisplayName(
      room: room,
      matrixUserId: matrixUserId,
    );
    final normalizedDisplayName = displayName?.trim() ?? '';
    if (normalizedDisplayName.isEmpty) {
      return match.group(0) ?? '';
    }

    final mentionDisplayName = normalizedDisplayName.startsWith('@')
        ? normalizedDisplayName.substring(1)
        : normalizedDisplayName;
    if (mentionDisplayName.isEmpty) {
      return match.group(0) ?? '';
    }

    final prefix = match.group(1) ?? '';
    return '$prefix@$mentionDisplayName';
  });
}

String? resolveMatrixMentionDisplayName({
  required Room room,
  required String? matrixUserId,
  String? fallbackDisplayName,
}) {
  final key = matrixUserId?.trim() ?? '';
  if (key.isEmpty) {
    return null;
  }

  final user = room.unsafeGetUserFromMemoryOrFallback(key);
  final fallback = _normalizeMentionFallbackDisplayName(
    matrixUserId: key,
    user: user,
    fallbackDisplayName: fallbackDisplayName,
  );
  AgentService.instance.ensureMatrixProfilePresentationById(
    client: room.client,
    matrixUserId: key,
    fallbackDisplayName: fallback,
    fallbackAvatarUri: user.avatarUrl,
  );

  final displayName = AgentService.instance.resolveDisplayName(
    user,
    fallbackDisplayName: fallback,
  );
  final normalizedDisplayName = displayName.trim();
  if (normalizedDisplayName.isEmpty) {
    return null;
  }
  return normalizedDisplayName;
}

String _normalizeMentionFallbackDisplayName({
  required String matrixUserId,
  required User user,
  String? fallbackDisplayName,
}) {
  final normalizedFallback = fallbackDisplayName?.trim() ?? '';
  if (normalizedFallback.isNotEmpty && normalizedFallback != matrixUserId) {
    return normalizedFallback;
  }

  final userDisplayName = user.calcDisplayname().trim();
  if (userDisplayName.isNotEmpty && userDisplayName != matrixUserId) {
    return userDisplayName;
  }

  return matrixUserId.localpart ?? matrixUserId;
}
