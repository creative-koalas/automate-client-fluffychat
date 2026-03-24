import 'package:matrix/matrix.dart';

import 'package:psygo/services/agent_service.dart';

extension AgentUserPresentationExtension on User {
  String calcDisplaynameWithAgents({MatrixLocalizations? i18n}) {
    final agentService = AgentService.instance;
    agentService.ensureMatrixProfilePresentation(this);
    final fallbackDisplayName =
        i18n == null ? calcDisplayname() : calcDisplayname(i18n: i18n);
    return agentService.resolveDisplayNameByMatrixUserId(
      id,
      fallbackDisplayName: fallbackDisplayName,
    );
  }

  Uri? get avatarUrlWithAgents {
    final agentService = AgentService.instance;
    agentService.ensureMatrixProfilePresentation(this);
    return agentService.resolveAvatarUriByMatrixUserId(
      id,
      fallbackAvatarUri: avatarUrl,
    );
  }

  ({Uri? avatarUrl, String displayName}) getPresentation({
    MatrixLocalizations? i18n,
  }) {
    return (
      avatarUrl: avatarUrlWithAgents,
      displayName: calcDisplaynameWithAgents(i18n: i18n),
    );
  }
}

extension AgentRoomPresentationExtension on Room {
  String getLocalizedDisplaynameWithAgents(MatrixLocalizations i18n) {
    final directChatMatrixId = directChatMatrixID;
    if (directChatMatrixId == null) {
      return getLocalizedDisplayname(i18n);
    }
    final user = unsafeGetUserFromMemoryOrFallback(directChatMatrixId);
    final agentService = AgentService.instance;
    agentService.ensureMatrixProfilePresentationById(
      client: client,
      matrixUserId: directChatMatrixId,
      fallbackDisplayName: user.displayName ?? user.calcDisplayname(i18n: i18n),
      fallbackAvatarUri: user.avatarUrl,
    );
    return agentService.resolveDisplayNameByMatrixUserId(
      directChatMatrixId,
      fallbackDisplayName: user.calcDisplayname(i18n: i18n),
    );
  }
}

extension AgentEventPresentationExtension on Event {
  Future<String> calcLocalizedBodyWithAgents(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) async {
    if (redacted) {
      await redactedBecause?.fetchSenderUser();
    }

    if ({
          EventTypes.Message,
          EventTypes.Sticker,
          EventTypes.CallInvite,
          PollEventContent.startType,
        }.contains(type) ||
        type.contains(EventTypes.Encrypted)) {
      await fetchSenderUser();
    }

    return calcLocalizedBodyFallbackWithAgents(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
  }

  String calcLocalizedBodyFallbackWithAgents(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    if (redacted) {
      return calcLocalizedBodyFallback(
        i18n,
        withSenderNamePrefix: withSenderNamePrefix,
        hideReply: hideReply,
        hideEdit: hideEdit,
        plaintextBody: plaintextBody,
        removeMarkdown: removeMarkdown,
      );
    }

    final senderDisplayName =
        senderFromMemoryOrFallback.calcDisplaynameWithAgents(i18n: i18n);
    final body = calcUnlocalizedBody(
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );

    String? localizedBody;
    switch (type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
        localizedBody = _localizedMessageBody(
          i18n,
          senderDisplayName: senderDisplayName,
          body: body,
        );
        break;
      case EventTypes.Sticker:
        localizedBody = i18n.sentASticker(senderDisplayName);
        break;
      case EventTypes.CallInvite:
        localizedBody = i18n.startedACall(senderDisplayName);
        break;
      case PollEventContent.startType:
        localizedBody = i18n.startedAPoll(senderDisplayName);
        break;
    }

    if (localizedBody == null) {
      return calcLocalizedBodyFallback(
        i18n,
        withSenderNamePrefix: withSenderNamePrefix,
        hideReply: hideReply,
        hideEdit: hideEdit,
        plaintextBody: plaintextBody,
        removeMarkdown: removeMarkdown,
      );
    }

    if (withSenderNamePrefix &&
        type == EventTypes.Message &&
        Event.textOnlyMessageTypes.contains(messageType)) {
      final senderNameOrYou =
          senderId == room.client.userID ? i18n.you : senderDisplayName;
      localizedBody = '$senderNameOrYou: $localizedBody';
    }

    return localizedBody;
  }

  String? _localizedMessageBody(
    MatrixLocalizations i18n, {
    required String senderDisplayName,
    required String body,
  }) {
    switch (messageType) {
      case MessageTypes.Image:
        return i18n.sentAPicture(senderDisplayName);
      case MessageTypes.File:
        return i18n.sentAFile(senderDisplayName);
      case MessageTypes.Audio:
        if (content.tryGetMap('org.matrix.msc3245.voice') != null) {
          final durationInt = content
              .tryGetMap<String, Object?>('info')
              ?.tryGet<int>('duration');
          return i18n.voiceMessage(
            senderDisplayName,
            durationInt == null ? null : Duration(milliseconds: durationInt),
          );
        }
        return i18n.sentAnAudio(senderDisplayName);
      case MessageTypes.Video:
        return i18n.sentAVideo(senderDisplayName);
      case MessageTypes.Location:
        return i18n.sharedTheLocation(senderDisplayName);
      case MessageTypes.Sticker:
        return i18n.sentASticker(senderDisplayName);
      case MessageTypes.Emote:
        return '* $body';
      case EventTypes.KeyVerificationRequest:
        return i18n.requestedKeyVerification(senderDisplayName);
      case EventTypes.KeyVerificationCancel:
        return i18n.canceledKeyVerification(senderDisplayName);
      case EventTypes.KeyVerificationDone:
        return i18n.completedKeyVerification(senderDisplayName);
      case EventTypes.KeyVerificationReady:
        return i18n.isReadyForKeyVerification(senderDisplayName);
      case EventTypes.KeyVerificationAccept:
        return i18n.acceptedKeyVerification(senderDisplayName);
      case EventTypes.KeyVerificationStart:
        return i18n.startedKeyVerification(senderDisplayName);
      case MessageTypes.BadEncrypted:
      case MessageTypes.Text:
      case MessageTypes.Notice:
      case MessageTypes.None:
      default:
        return body;
    }
  }
}
