class BibleSettings {
  final double fontSize;
  final double lineHeight;
  final bool isDarkMode;

  /// When true, cross-references are auto-expanded inline for every verse that
  /// has 1–2 of them (verses with more open a dedicated page). When false (the
  /// default), the reader shows only a small badge and the user taps it to
  /// reveal references.
  final bool expandCrossReferences;

  // Reading progress (last visited location).
  final String? lastVersion;
  final String? lastBook;
  final int lastChapter;

  const BibleSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.isDarkMode = false,
    this.expandCrossReferences = false,
    this.lastVersion,
    this.lastBook,
    this.lastChapter = 1,
  });

  bool get hasProgress => lastBook != null;

  BibleSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? isDarkMode,
    bool? expandCrossReferences,
    String? lastVersion,
    String? lastBook,
    int? lastChapter,
  }) {
    return BibleSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      expandCrossReferences:
          expandCrossReferences ?? this.expandCrossReferences,
      lastVersion: lastVersion ?? this.lastVersion,
      lastBook: lastBook ?? this.lastBook,
      lastChapter: lastChapter ?? this.lastChapter,
    );
  }
}
