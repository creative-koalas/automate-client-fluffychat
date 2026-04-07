import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';

String resolveDisplayNameForMatrixUserId({
  required Room room,
  required String? matrixUserId,
  required MatrixLocalizations matrixLocals,
  bool allowGroupDisplayName = true,
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
  if (allowGroupDisplayName && !room.isDirectChat) {
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

bool shouldUseGroupDisplayNameForUnnamedRoomMembers({
  required int memberCount,
  required bool isDirectChat,
  required bool isAbandonedDMRoom,
}) {
  if (isDirectChat || isAbandonedDMRoom) {
    return false;
  }
  return memberCount != 1;
}

String? resolveRoomDisplayNameFromMemberNames({
  required List<String> memberNames,
  required bool isDirectChat,
  required bool isAbandonedDMRoom,
  required MatrixLocalizations matrixLocals,
}) {
  if (memberNames.isEmpty) {
    return null;
  }

  final joinedNames = memberNames.join(', ');
  if (isAbandonedDMRoom) {
    return matrixLocals.wasDirectChatDisplayName(joinedNames);
  }
  if (isDirectChat || memberNames.length == 1) {
    return joinedNames;
  }
  return matrixLocals.groupWith(joinedNames);
}

String resolveRoomDisplayNameWithMatrixLocals({
  required Room room,
  required MatrixLocalizations matrixLocals,
}) {
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

  final visibleHeroIds = heroIds
      .where((heroId) => heroId.isNotEmpty && heroId != room.client.userID)
      .toList(growable: false);
  final useGroupDisplayName = shouldUseGroupDisplayNameForUnnamedRoomMembers(
    memberCount: visibleHeroIds.length,
    isDirectChat: room.isDirectChat,
    isAbandonedDMRoom: room.isAbandonedDMRoom,
  );

  final names = <String>[];
  for (final heroId in visibleHeroIds) {
    final resolvedName = resolveDisplayNameForMatrixUserId(
      room: room,
      matrixUserId: heroId,
      matrixLocals: matrixLocals,
      allowGroupDisplayName: useGroupDisplayName,
    ).trim();
    if (resolvedName.isNotEmpty) {
      names.add(resolvedName);
    }
  }

  final resolvedFromMembers = resolveRoomDisplayNameFromMemberNames(
    memberNames: names,
    isDirectChat: room.isDirectChat,
    isAbandonedDMRoom: room.isAbandonedDMRoom,
    matrixLocals: matrixLocals,
  );
  if (resolvedFromMembers != null) {
    return resolvedFromMembers;
  }

  return room.getLocalizedDisplayname(matrixLocals);
}

String resolveRoomDisplayName({
  required Room room,
  required L10n l10n,
}) {
  final matrixLocals = MatrixLocals(l10n);
  return resolveRoomDisplayNameWithMatrixLocals(
    room: room,
    matrixLocals: matrixLocals,
  );
}
