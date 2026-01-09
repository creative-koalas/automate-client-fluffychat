import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:psygo/l10n/l10n.dart';
import '../../widgets/matrix.dart';

class EncryptionButton extends StatelessWidget {
  final Room room;
  const EncryptionButton(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<SyncUpdate>(
      stream: Matrix.of(context)
          .client
          .onSync
          .stream
          .where((s) => s.deviceLists != null),
      builder: (context, snapshot) {
        final shouldBeEncrypted = room.joinRules != JoinRules.public;
        return FutureBuilder<EncryptionHealthState>(
          future: room.encrypted
              ? room.calcEncryptionHealthState()
              : Future.value(EncryptionHealthState.allVerified),
          builder: (BuildContext context, snapshot) {
            final isEncrypted = room.encrypted;
            final hasUnverified =
                snapshot.data == EncryptionHealthState.unverifiedDevices;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isEncrypted
                    ? (hasUnverified
                        ? theme.colorScheme.errorContainer.withAlpha(60)
                        : Colors.green.withAlpha(20))
                    : (shouldBeEncrypted
                        ? theme.colorScheme.errorContainer.withAlpha(60)
                        : theme.colorScheme.surfaceContainerHighest.withAlpha(100)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                tooltip: isEncrypted
                    ? L10n.of(context).encrypted
                    : L10n.of(context).encryptionNotEnabled,
                icon: b.Badge(
                  badgeAnimation: const b.BadgeAnimation.fade(),
                  showBadge: hasUnverified,
                  badgeStyle: b.BadgeStyle(
                    badgeColor: theme.colorScheme.error,
                    elevation: 4,
                  ),
                  badgeContent: Text(
                    '!',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Icon(
                    isEncrypted
                        ? Icons.lock_rounded
                        : Icons.no_encryption_rounded,
                    size: 20,
                    color: isEncrypted
                        ? (hasUnverified
                            ? theme.colorScheme.error
                            : Colors.green)
                        : (shouldBeEncrypted
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                onPressed: () => context.go('/rooms/${room.id}/encryption'),
              ),
            );
          },
        );
      },
    );
  }
}
