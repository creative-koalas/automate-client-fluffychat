String replaceLocalizedSenderPrefix({
  required String text,
  required String originalSenderName,
  required String resolvedSenderName,
}) {
  final from = originalSenderName.trim();
  final to = resolvedSenderName.trim();
  if (text.isEmpty || from.isEmpty || to.isEmpty || from == to) {
    return text;
  }

  final prefix = '$from: ';
  if (!text.startsWith(prefix)) {
    return text;
  }

  return '$to: ${text.substring(prefix.length)}';
}
