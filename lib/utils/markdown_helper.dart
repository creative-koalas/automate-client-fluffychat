import 'package:markdown/markdown.dart' as md;

/// Helper class for Markdown detection and conversion
class MarkdownHelper {
  // Patterns that indicate Markdown content
  static final RegExp _markdownPatterns = RegExp(
    r'(\*\*[^*]+\*\*)|'  // bold **text**
    r'(\*[^*]+\*)|'       // italic *text*
    r'(__[^_]+__)|'       // bold __text__
    r'(_[^_]+_)|'         // italic _text_
    r'(~~[^~]+~~)|'       // strikethrough ~~text~~
    r'(`[^`]+`)|'         // inline code `code`
    r'(```[\s\S]*?```)|'  // code block ```code```
    r'(^#{1,6}\s)|'       // headers # ## ### etc
    r'(^\s*[-*+]\s)|'     // unordered list - * +
    r'(^\s*\d+\.\s)|'     // ordered list 1. 2. 3.
    r'(\[.+?\]\(.+?\))|'  // links [text](url)
    r'(^>\s)',            // blockquote > text
    multiLine: true,
  );

  /// Check if text contains Markdown patterns
  static bool containsMarkdown(String text) {
    return _markdownPatterns.hasMatch(text);
  }

  /// Convert Markdown to HTML
  static String toHtml(String markdown) {
    return md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: [
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
      ],
    );
  }

  /// Convert Markdown to HTML only if it contains Markdown patterns
  /// Otherwise return the original text
  static String toHtmlIfNeeded(String text) {
    if (containsMarkdown(text)) {
      return toHtml(text);
    }
    return text;
  }
}
