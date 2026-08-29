class BibleSettings {
  final double fontSize;
  final double lineHeight;
  final bool isDarkMode;

  const BibleSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.isDarkMode = false,
  });

  BibleSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? isDarkMode,
  }) {
    return BibleSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }
}
