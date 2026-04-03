final RegExp _inputMentionTerminatorPattern = RegExp(
  r'[\s\)\]\}>，。！？、；：,.!?]',
  unicode: true,
);

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

InputMentionQuery? findActiveInputMentionQuery({
  required String text,
  required int cursorOffset,
}) {
  if (text.isEmpty) {
    return null;
  }

  final safeOffset = cursorOffset.clamp(0, text.length);
  final searchText = text.substring(0, safeOffset);
  final mentionStart = searchText.lastIndexOf('@');
  if (mentionStart < 0) {
    return null;
  }

  final query = searchText.substring(mentionStart + 1);
  if (query.contains('@') || _inputMentionTerminatorPattern.hasMatch(query)) {
    return null;
  }

  return InputMentionQuery(
    start: mentionStart,
    end: safeOffset,
    token: searchText.substring(mentionStart, safeOffset),
    query: query,
  );
}
