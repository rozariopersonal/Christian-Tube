import 'package:mobile/core/engines/base_feed_engine.dart';

class ScriptureFilterState extends BaseFeedFilterState {
  final String activeVersionId;
  final double fontSizeScale;
  final String activeFontFamily;
  final String textColorHex;
  final bool isBold;
  final bool isItalic;
  final String textAlign; // 'left', 'center', 'right'
  final String backgroundPreset;
  final String? bookFilter;
  final String? testamentFilter;
  final String? comparisonVersionId;
  final String readingOrder; // 'random', 'canonical', 'bookmarked'
  final List<String> selectedCategories;
  final List<String> selectedTags;

  const ScriptureFilterState({
    this.activeVersionId = 'NASB',
    this.fontSizeScale = 1.0,
    this.activeFontFamily = 'Playfair',
    this.textColorHex = '#FFFFFF',
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = 'center',
    this.backgroundPreset = 'mountain_dawn',
    this.bookFilter,
    this.testamentFilter,
    this.comparisonVersionId,
    this.readingOrder = 'random',
    this.selectedCategories = const [],
    this.selectedTags = const [],
  });

  int get activeFilterCount {
    int count = 0;
    if (readingOrder != 'random') count++;
    if (testamentFilter != null && testamentFilter != 'All') count++;
    if (bookFilter != null && bookFilter != 'All Books') count++;
    count += selectedCategories.length;
    count += selectedTags.length;
    return count;
  }

  ScriptureFilterState copyWith({
    String? activeVersionId,
    double? fontSizeScale,
    String? activeFontFamily,
    String? textColorHex,
    bool? isBold,
    bool? isItalic,
    String? textAlign,
    String? backgroundPreset,
    String? bookFilter,
    String? testamentFilter,
    String? comparisonVersionId,
    String? readingOrder,
    List<String>? selectedCategories,
    List<String>? selectedTags,
    bool clearBookFilter = false,
    bool clearTestamentFilter = false,
    bool clearComparisonVersion = false,
  }) {
    return ScriptureFilterState(
      activeVersionId: activeVersionId ?? this.activeVersionId,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      activeFontFamily: activeFontFamily ?? this.activeFontFamily,
      textColorHex: textColorHex ?? this.textColorHex,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      textAlign: textAlign ?? this.textAlign,
      backgroundPreset: backgroundPreset ?? this.backgroundPreset,
      bookFilter: clearBookFilter ? null : (bookFilter ?? this.bookFilter),
      testamentFilter: clearTestamentFilter ? null : (testamentFilter ?? this.testamentFilter),
      comparisonVersionId: clearComparisonVersion
          ? null
          : (comparisonVersionId ?? this.comparisonVersionId),
      readingOrder: readingOrder ?? this.readingOrder,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      selectedTags: selectedTags ?? this.selectedTags,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptureFilterState &&
          runtimeType == other.runtimeType &&
          activeVersionId == other.activeVersionId &&
          fontSizeScale == other.fontSizeScale &&
          activeFontFamily == other.activeFontFamily &&
          textColorHex == other.textColorHex &&
          isBold == other.isBold &&
          isItalic == other.isItalic &&
          textAlign == other.textAlign &&
          backgroundPreset == other.backgroundPreset &&
          bookFilter == other.bookFilter &&
          testamentFilter == other.testamentFilter &&
          comparisonVersionId == other.comparisonVersionId &&
          readingOrder == other.readingOrder &&
          _listEquals(selectedCategories, other.selectedCategories) &&
          _listEquals(selectedTags, other.selectedTags);

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        activeVersionId,
        fontSizeScale,
        activeFontFamily,
        textColorHex,
        isBold,
        isItalic,
        textAlign,
        backgroundPreset,
        bookFilter,
        testamentFilter,
        comparisonVersionId,
        readingOrder,
        Object.hashAll(selectedCategories),
        Object.hashAll(selectedTags),
      );
}
