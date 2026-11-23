/// Extracts short, readable highlights from a GitHub release body.
List<String> releaseHighlights(String notes) {
  final highlights = <String>[];
  for (final line in notes.split('\n')) {
    final trimmed = line.trim();
    if (trimmed == '---' ||
        RegExp(
          r'^\*\*Direct Download\*\*',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
      break;
    }
    final match = RegExp(r'^(?:[-*•]|\d+\.)\s+(.+)$').firstMatch(trimmed);
    if (match == null) continue;
    var text = match
        .group(1)!
        .replaceAllMapped(
          RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
          (match) => match.group(1)!,
        )
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'[*_`]'), '')
        .trim();
    if (text.isEmpty ||
        RegExp(
          r'https?://|\b(?:apk|qr code)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
      continue;
    }
    text = text.replaceFirst(RegExp(r'^\w[\w -]{0,24}:\s*'), '');
    if (text.isNotEmpty) highlights.add(text);
    if (highlights.length == 4) break;
  }
  return highlights;
}
