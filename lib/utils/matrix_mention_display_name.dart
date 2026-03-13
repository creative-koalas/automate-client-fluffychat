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

    AgentService.instance.ensureMatrixProfilePresentationById(
      client: room.client,
      matrixUserId: matrixUserId,
      fallbackDisplayName: matrixUserId.localpart,
    );

    final displayName =
        AgentService.instance.tryResolveDisplayNameByMatrixUserId(matrixUserId);
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
