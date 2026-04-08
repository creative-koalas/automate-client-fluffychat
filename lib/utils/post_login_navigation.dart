import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

import '../core/auth_storage_keys.dart';
import '../models/agent.dart';
import '../repositories/agent_repository.dart';
import '../repositories/agent_template_repository.dart';
import '../services/agent_service.dart';

const String _defaultFirstBotName = 'OpenOcto';
const int _maxAutoRecruitBotCount = 3;
const String _defaultBotHandledKeyPrefix = 'automate_default_first_bot_handled';

Future<String>? _resolvePostLoginDestinationInFlight;

/// Resolve post-login destination based on whether the user has any employees.
Future<String> resolvePostLoginDestination({
  Client? matrixClient,
}) async {
  final inFlight = _resolvePostLoginDestinationInFlight;
  if (inFlight != null) {
    return inFlight;
  }

  final future = _resolvePostLoginDestinationInternal(matrixClient: matrixClient);
  _resolvePostLoginDestinationInFlight = future;
  try {
    return await future;
  } finally {
    if (identical(_resolvePostLoginDestinationInFlight, future)) {
      _resolvePostLoginDestinationInFlight = null;
    }
  }
}

Future<String> _resolvePostLoginDestinationInternal({
  Client? matrixClient,
}) async {
  final repository = AgentRepository();
  try {
    final page = await repository.getUserAgents(
      limit: _maxAutoRecruitBotCount,
      forceRefresh: true,
    );
    final needsDefaultBot = await _needsDefaultBotOnLogin();
    if (needsDefaultBot) {
      final existingBotRoute = await _resolveExistingBotChatRoute(
        page.agents,
        matrixClient,
      );
      if (existingBotRoute != null) {
        await _markDefaultBotCompleted();
        debugPrint(
          '[PostLoginNavigation] Reusing existing bot chat route=$existingBotRoute',
        );
        return existingBotRoute;
      }

      final canAutoRecruit =
          page.agents.isEmpty &&
          page.agents.length < _maxAutoRecruitBotCount &&
          !page.hasNextPage;
      if (canAutoRecruit) {
        final autoRecruitedRoute = await _autoRecruitDefaultBotRoute(
          matrixClient,
        );
        if (autoRecruitedRoute != null) {
          await _markDefaultBotCompleted();
          debugPrint(
            '[PostLoginNavigation] Auto recruited default bot route=$autoRecruitedRoute',
          );
          return autoRecruitedRoute;
        }
      }
    }

    final destination = needsDefaultBot
        ? '/rooms/team'
        : (page.agents.isEmpty ? '/rooms/team' : '/rooms');
    debugPrint(
      '[PostLoginNavigation] Resolved by API: employees=${page.agents.length}, '
      'needsDefaultBot=$needsDefaultBot, destination=$destination',
    );
    return destination;
  } finally {
    repository.dispose();
  }
}

Future<bool> _needsDefaultBotOnLogin() async {
  const storage = FlutterSecureStorage();
  final onboardingRaw = await storage.read(
    key: AuthStorageKeys.scoped('automate_onboarding_completed'),
  );
  if (onboardingRaw == null || onboardingRaw.toLowerCase() == 'true') {
    return false;
  }

  final userId = await storage.read(key: AuthStorageKeys.userId);
  final normalizedUserId = userId?.trim() ?? '';
  if (normalizedUserId.isEmpty) {
    return true;
  }

  final handledRaw = await storage.read(
    key: _defaultBotHandledKey(normalizedUserId),
  );
  return handledRaw?.toLowerCase() != 'true';
}

Future<void> _markDefaultBotCompleted() async {
  const storage = FlutterSecureStorage();
  final userId = await storage.read(key: AuthStorageKeys.userId);
  final normalizedUserId = userId?.trim() ?? '';
  if (normalizedUserId.isEmpty) {
    return;
  }
  await storage.write(
    key: _defaultBotHandledKey(normalizedUserId),
    value: 'true',
  );
}

String _defaultBotHandledKey(String userId) {
  final normalizedUserId =
      userId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  return AuthStorageKeys.scoped(
    '$_defaultBotHandledKeyPrefix.$normalizedUserId',
  );
}

Future<String?> _resolveExistingBotChatRoute(
  List<Agent> agents,
  Client? matrixClient,
) async {
  if (matrixClient == null) {
    return null;
  }

  final preferredAgent =
      agents.firstWhereOrNull(
        (agent) =>
            agent.matrixUserId?.trim().isNotEmpty == true &&
            agent.displayName.trim().toLowerCase() ==
                _defaultFirstBotName.toLowerCase(),
      ) ??
      agents.firstWhereOrNull(
        (agent) => agent.matrixUserId?.trim().isNotEmpty == true,
      );
  final matrixUserId = preferredAgent?.matrixUserId?.trim() ?? '';
  if (matrixUserId.isEmpty) {
    return null;
  }
  return _ensureDirectChatRoute(matrixClient, matrixUserId);
}

Future<String?> _autoRecruitDefaultBotRoute(Client? matrixClient) async {
  if (matrixClient == null) {
    return null;
  }

  final repository = AgentTemplateRepository();
  try {
    final accepted = await repository.createCustomAgentWithPlugins(
      name: _defaultFirstBotName,
      plugins: null,
    );
    final result = await repository.waitCreateOperation(accepted.operationId);
    final matrixUserId = result.matrixUserId.trim();
    if (matrixUserId.isEmpty) {
      debugPrint(
        '[PostLoginNavigation] Auto recruit succeeded but matrix_user_id is empty',
      );
      return null;
    }

    await AgentService.instance.refresh(forceRefresh: true);
    return _ensureDirectChatRoute(matrixClient, matrixUserId);
  } catch (e) {
    debugPrint('[PostLoginNavigation] Auto recruit default bot failed: $e');
    return null;
  } finally {
    repository.dispose();
  }
}

Future<String> _ensureDirectChatRoute(
  Client matrixClient,
  String matrixUserId,
) async {
  final existingDmRoomId = matrixClient.getDirectChatFromUserId(matrixUserId);
  if (existingDmRoomId != null && existingDmRoomId.isNotEmpty) {
    return '/rooms/$existingDmRoomId';
  }

  final roomId = await matrixClient.startDirectChat(
    matrixUserId,
    enableEncryption: false,
  );
  return '/rooms/$roomId';
}
