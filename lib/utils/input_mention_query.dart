const String _asciiMentionTrigger = '@';
const String _fullWidthMentionTrigger = '＠';

final RegExp _inputMentionTerminatorPattern = RegExp(
  r'[\s\)\]\}>，。！？、；：,.!?]',
  unicode: true,
);
final RegExp _inputMentionWhitespacePattern = RegExp(r'\s', unicode: true);

class InputMentionQuery {
  final int start;
  final int end;
  final String token;
  final String query;

  const InputMentionQuery({
    required this.start,
    required this.end,
    required this.token,
    required this.query,
  });
}

class InputMentionDeleteRange {
  final int start;
  final int end;

  const InputMentionDeleteRange({
    required this.start,
    required this.end,
  });
}

InputMentionQuery? findActiveInputMentionQuery({
  required String text,
  required int cursorOffset,
}) {
  if (text.isEmpty) {
    return null;
  }

  final safeOffset = cursorOffset.clamp(0, text.length);
  final searchText = text.substring(0, safeOffset);
  final mentionStart = _lastInputMentionTriggerIndex(searchText);
  if (mentionStart < 0) {
    return null;
  }

  final query = searchText.substring(mentionStart + 1);
  if (_containsInputMentionTrigger(query) ||
      _inputMentionTerminatorPattern.hasMatch(query)) {
    return null;
  }

  return InputMentionQuery(
    start: mentionStart,
    end: safeOffset,
    token: searchText.substring(mentionStart, safeOffset),
    query: query,
  );
}

InputMentionDeleteRange? findWholeInputMentionDeleteRange({
  required String text,
  required int cursorOffset,
  required Iterable<String> mentionTokens,
}) {
  if (text.isEmpty || cursorOffset <= 0) {
    return null;
  }

  final safeOffset = cursorOffset.clamp(0, text.length);
  final normalizedMentionTokens = mentionTokens
      .where((token) => token.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (normalizedMentionTokens.isEmpty) {
    return null;
  }

  InputMentionDeleteRange? deleteRange;
  final previousCharacter = text[safeOffset - 1];
  if (previousCharacter == ' ') {
    final mentionRange = _findMentionTokenRangeEndingAt(
      text: text,
      end: safeOffset - 1,
      mentionTokens: normalizedMentionTokens,
    );
    if (mentionRange != null) {
      deleteRange = InputMentionDeleteRange(
        start: mentionRange.start,
        end: safeOffset,
      );
    }
  }

  deleteRange ??= _findMentionTokenRangeEndingAt(
    text: text,
    end: safeOffset,
    mentionTokens: normalizedMentionTokens,
  );
  if (deleteRange == null) {
    return null;
  }

  final expandedStart = _expandMentionDeletionStart(
    text: text,
    mentionStart: deleteRange.start,
  );
  return InputMentionDeleteRange(
    start: expandedStart,
    end: deleteRange.end,
  );
}

InputMentionDeleteRange? _findMentionTokenRangeEndingAt({
  required String text,
  required int end,
  required List<String> mentionTokens,
}) {
  if (end <= 0 || end > text.length) {
    return null;
  }

  for (final token in mentionTokens) {
    final start = end - token.length;
    if (start < 0) {
      continue;
    }
    if (text.substring(start, end) != token) {
      continue;
    }
    return InputMentionDeleteRange(start: start, end: end);
  }

  return null;
}

int _expandMentionDeletionStart({
  required String text,
  required int mentionStart,
}) {
  if (mentionStart <= 0 || text[mentionStart - 1] != ' ') {
    return mentionStart;
  }
  if (mentionStart == 1) {
    return mentionStart - 1;
  }

  final previousCharacter = text[mentionStart - 2];
  if (_inputMentionWhitespacePattern.hasMatch(previousCharacter)) {
    return mentionStart;
  }
  return mentionStart - 1;
}

int _lastInputMentionTriggerIndex(String text) {
  final asciiIndex = text.lastIndexOf(_asciiMentionTrigger);
  final fullWidthIndex = text.lastIndexOf(_fullWidthMentionTrigger);
  return asciiIndex > fullWidthIndex ? asciiIndex : fullWidthIndex;
}

bool _containsInputMentionTrigger(String text) =>
    text.contains(_asciiMentionTrigger) ||
    text.contains(_fullWidthMentionTrigger);
