import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';

String resolveDisplayNameForMatrixUserId({
  required Room room,
  required String? matrixUserId,
  required MatrixLocals matrixLocals,
}) {
  final key = matrixUserId?.trim() ?? '';
  if (key.isEmpty) {
    return '';
  }
  final user = room.unsafeGetUserFromMemoryOrFallback(key);
  AgentService.instance.ensureMatrixProfilePresentationById(
    client: room.client,
    matrixUserId: key,
    fallbackDisplayName:
        user.displayName ?? user.calcDisplayname(i18n: matrixLocals),
    fallbackAvatarUri: user.avatarUrl,
  );
  if (!room.isDirectChat) {
    AgentService.instance.ensureGroupDisplayNameByMatrixUserId(key);
    final groupDisplayName =
        AgentService.instance.tryResolveGroupDisplayNameByMatrixUserId(key);
    if (groupDisplayName != null) {
      return groupDisplayName;
    }
  }
  return AgentService.instance.resolveDisplayNameByMatrixUserId(
    key,
    fallbackDisplayName: user.calcDisplayname(i18n: matrixLocals),
  );
}

String resolveRoomDisplayName({
  required Room room,
  required L10n l10n,
}) {
  final matrixLocals = MatrixLocals(l10n);

  if (room.name.isNotEmpty) {
    return room.name;
  }

  final canonicalAlias = room.canonicalAlias.localpart;
  if (canonicalAlias != null && canonicalAlias.isNotEmpty) {
    return canonicalAlias;
  }

  final directChatMatrixId = room.directChatMatrixID;
  final heroIds = <String>[...?room.summary.mHeroes];
  if (directChatMatrixId != null && heroIds.isEmpty) {
    heroIds.add(directChatMatrixId);
  }

  final names = <String>[];
  for (final heroId in heroIds) {
    if (heroId.isEmpty || heroId == room.client.userID) {
      continue;
    }
    final resolvedName = resolveDisplayNameForMatrixUserId(
      room: room,
      matrixUserId: heroId,
      matrixLocals: matrixLocals,
    ).trim();
    if (resolvedName.isNotEmpty) {
      names.add(resolvedName);
    }
  }

  if (names.isNotEmpty) {
    final joinedNames = names.join(', ');
    if (room.isAbandonedDMRoom) {
      return l10n.wasDirectChatDisplayName(joinedNames);
    }
    return room.isDirectChat ? joinedNames : l10n.groupWith(joinedNames);
  }

  return room.getLocalizedDisplayname(matrixLocals);
}
