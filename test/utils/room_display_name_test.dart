import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/room_display_name.dart';

void main() {
  group('shouldUseGroupDisplayNameForUnnamedRoomMembers', () {
    test('disables group display names for unnamed one-member groups', () {
      final useGroupDisplayName =
          shouldUseGroupDisplayNameForUnnamedRoomMembers(
        memberCount: 1,
        isDirectChat: false,
        isAbandonedDMRoom: false,
      );

      expect(useGroupDisplayName, isFalse);
    });

    test('keeps group display names for unnamed multi-member groups', () {
      final useGroupDisplayName =
          shouldUseGroupDisplayNameForUnnamedRoomMembers(
        memberCount: 2,
        isDirectChat: false,
        isAbandonedDMRoom: false,
      );

      expect(useGroupDisplayName, isTrue);
    });
  });

  group('resolveRoomDisplayNameFromMemberNames', () {
    late MatrixLocals matrixLocals;

    setUp(() async {
      matrixLocals = MatrixLocals(await lookupL10n(const Locale('zh')));
    });

    test('uses the single member name for unnamed one-member groups', () {
      final displayName = resolveRoomDisplayNameFromMemberNames(
        memberNames: const ['Support Bot'],
        isDirectChat: false,
        isAbandonedDMRoom: false,
        matrixLocals: matrixLocals,
      );

      expect(displayName, 'Support Bot');
    });

    test('keeps the group fallback for unnamed multi-member groups', () {
      final displayName = resolveRoomDisplayNameFromMemberNames(
        memberNames: const ['Support Bot', 'Second Bot'],
        isDirectChat: false,
        isAbandonedDMRoom: false,
        matrixLocals: matrixLocals,
      );

      expect(displayName, 'Support Bot, Second Bot 的群组');
    });
  });
}
