class BibleSettings {
  final double fontSize;
  final double lineHeight;
  final bool isDarkMode;

  // Reading progress (last visited location).
  final String? lastVersion;
  final String? lastBook;
  final int lastChapter;

  const BibleSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.isDarkMode = false,
    this.lastVersion,
    this.lastBook,
    this.lastChapter = 1,
  });

  bool get hasProgress => lastBook != null;

  BibleSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? isDarkMode,
    String? lastVersion,
    String? lastBook,
    int? lastChapter,
  }) {
    return BibleSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      lastVersion: lastVersion ?? this.lastVersion,
      lastBook: lastBook ?? this.lastBook,
      lastChapter: lastChapter ?? this.lastChapter,
    );
  }
}
