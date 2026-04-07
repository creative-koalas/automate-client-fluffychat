import 'package:matrix/matrix.dart';
import 'package:psygo/services/agent_service.dart';

const int _maximumMentionHashLength = 10000;
const String _mentionBoundaryPunctuation = '()[]{}<>,.!?，。！？、；：';

String buildInputMentionByUser({
  required Room room,
  required User user,
}) {
  final normalizedDisplayName = _normalizedDisplayName(
    AgentService.instance.resolveDisplayName(user),
  );
  if (normalizedDisplayName == null) {
    return user.id;
  }

  final identifier = _identifierFromDisplayName(normalizedDisplayName);
  if (identifier == null) {
    return user.id;
  }

  final duplicateExists = room.getParticipants().any((participant) {
    if (participant.id == user.id) {
      return false;
    }
    final participantDisplayName = _normalizedDisplayName(
      AgentService.instance.resolveDisplayName(participant),
    );
    return participantDisplayName == normalizedDisplayName;
  });
  if (!duplicateExists) {
    return identifier;
  }

  final ourHash = _mentionHash(user.id);
  final hashCollision = room.getParticipants().any((participant) {
    if (participant.id == user.id) {
      return false;
    }
    return _mentionHash(participant.id) == ourHash;
  });
  if (hashCollision) {
    return user.id;
  }
  return '$identifier#$ourHash';
}

String replaceInputMentionsWithMatrixIds({
  required Room room,
  required String text,
}) {
  if (text.isEmpty || !text.contains('@')) {
    return text;
  }

  final mentionToUserId = <String, String>{};
  for (final participant in room.getParticipants()) {
    AgentService.instance.ensureMatrixProfilePresentation(participant);
    final mention = buildInputMentionByUser(
      room: room,
      user: participant,
    );
    if (mention.isEmpty || mention == participant.id || mention == '@room') {
      continue;
    }
    mentionToUserId[mention] = participant.id;
  }

  if (mentionToUserId.isEmpty) {
    return text;
  }

  final entries = mentionToUserId.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  var converted = normalizeInputMentionSpacing(
    text: text,
    mentionTokens: entries.map((entry) => entry.key),
  );

  for (final entry in entries) {
    final pattern = RegExp(
      '(^|[\\s\\(\\[\\{<，。！？、；：])(${RegExp.escape(entry.key)})(?=\$|[\\s\\)\\]\\}>，。！？、；：,.!?])',
      multiLine: true,
    );
    converted = converted.replaceAllMapped(
      pattern,
      (match) => '${match.group(1)}${entry.value}',
    );
  }

  return converted;
}

String normalizeInputMentionSpacing({
  required String text,
  required Iterable<String> mentionTokens,
}) {
  if (text.isEmpty || !text.contains('@')) {
    return text;
  }

  final mentions = mentionTokens
      .where((token) => token.isNotEmpty && token.startsWith('@'))
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (mentions.isEmpty) {
    return text;
  }

  final buffer = StringBuffer();
  String? lastOutputChar;
  var cursor = 0;

  while (cursor < text.length) {
    String? matchedMention;
    if (text[cursor] == '@' &&
        (lastOutputChar == null || _isMentionBoundaryChar(lastOutputChar))) {
      for (final mention in mentions) {
        if (text.startsWith(mention, cursor)) {
          matchedMention = mention;
          break;
        }
      }
    }

    if (matchedMention == null) {
      final char = text[cursor];
      buffer.write(char);
      lastOutputChar = char;
      cursor += 1;
      continue;
    }

    buffer.write(matchedMention);
    lastOutputChar = matchedMention[matchedMention.length - 1];
    cursor += matchedMention.length;

    if (cursor < text.length && !_isMentionBoundaryChar(text[cursor])) {
      buffer.write(' ');
      lastOutputChar = ' ';
    }
  }

  return buffer.toString();
}

String _mentionHash(String input) =>
    (input.codeUnits.fold<int>(0, (acc, unit) => acc + unit) %
            _maximumMentionHashLength)
        .toString();

bool _isMentionBoundaryChar(String char) {
  if (char.trim().isEmpty) {
    return true;
  }
  return _mentionBoundaryPunctuation.contains(char);
}

String? _normalizedDisplayName(String? raw) {
  var name = raw?.trim() ?? '';
  if (name.isEmpty) {
    return null;
  }
  if (name.startsWith('@')) {
    name = name.substring(1).trim();
  }
  if (name.isEmpty) {
    return null;
  }
  return name;
}

String? _identifierFromDisplayName(String displayName) {
  if (displayName.contains('[') || displayName.contains(']')) {
    return null;
  }
  final needsBracket = !RegExp(r'^\w+$').hasMatch(displayName);
  return needsBracket ? '@[$displayName]' : '@$displayName';
}
