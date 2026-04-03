class ChatTextToken {
  final String text;
  final bool isUrl;

  const ChatTextToken({
    required this.text,
    required this.isUrl,
  });
}

class ChatTextTokenizer {
  static final RegExp _plainUrlPattern = RegExp(
    r"https?:\/\/[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=%]+",
    caseSensitive: false,
  );

  const ChatTextTokenizer();

  bool containsUrl(String text) {
    if (text.isEmpty) return false;
    return text.contains('http://') || text.contains('https://');
  }

  List<ChatTextToken> tokenize(String text) {
    if (text.isEmpty) return const [];
    if (!containsUrl(text)) {
      return [ChatTextToken(text: text, isUrl: false)];
    }

    final tokens = <ChatTextToken>[];
    var cursor = 0;
    for (final match in _plainUrlPattern.allMatches(text)) {
      if (match.start > cursor) {
        tokens.add(
          ChatTextToken(
            text: text.substring(cursor, match.start),
            isUrl: false,
          ),
        );
      }

      final url = match.group(0);
      if (url != null && url.isNotEmpty) {
        tokens.add(ChatTextToken(text: url, isUrl: true));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      tokens.add(
        ChatTextToken(
          text: text.substring(cursor),
          isUrl: false,
        ),
      );
    }

    return tokens;
  }

  String? extractLeadingUrl(String text) {
    if (!containsUrl(text)) return null;
    final match = _plainUrlPattern.matchAsPrefix(text);
    return match?.group(0);
  }
}
