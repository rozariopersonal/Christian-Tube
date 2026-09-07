import 'package:mobile/core/engines/base_feed_engine.dart';

class WftwFilterState extends BaseFeedFilterState {
  final String activeVersionId;
  final double fontSizeScale;
  final String activeFontFamily;
  final String textColorHex;
  final bool isBold;
  final bool isItalic;
  final String textAlign;
  final String backgroundPreset;
  final int? yearFilter;
  final int? bookFilter;
  final String sortBy; // 'date' | 'book'
  final String? comparisonVersionId;

  const WftwFilterState({
    this.activeVersionId = 'TAOBVSI',
    this.fontSizeScale = 1.0,
    this.activeFontFamily = 'Playfair',
    this.textColorHex = '#FFFFFF',
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = 'center',
    this.backgroundPreset = 'mountain_dawn',
    this.yearFilter,
    this.bookFilter,
    this.sortBy = 'date',
    this.comparisonVersionId,
  });

  WftwFilterState copyWith({
    String? activeVersionId,
    double? fontSizeScale,
    String? activeFontFamily,
    String? textColorHex,
    bool? isBold,
    bool? isItalic,
    String? textAlign,
    String? backgroundPreset,
    int? yearFilter,
    int? bookFilter,
    String? sortBy,
    String? comparisonVersionId,
    bool clearYearFilter = false,
    bool clearBookFilter = false,
    bool clearComparisonVersion = false,
  }) {
    return WftwFilterState(
      activeVersionId: activeVersionId ?? this.activeVersionId,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      activeFontFamily: activeFontFamily ?? this.activeFontFamily,
      textColorHex: textColorHex ?? this.textColorHex,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      textAlign: textAlign ?? this.textAlign,
      backgroundPreset: backgroundPreset ?? this.backgroundPreset,
      yearFilter: clearYearFilter ? null : (yearFilter ?? this.yearFilter),
      bookFilter: clearBookFilter ? null : (bookFilter ?? this.bookFilter),
      sortBy: sortBy ?? this.sortBy,
      comparisonVersionId: clearComparisonVersion
          ? null
          : (comparisonVersionId ?? this.comparisonVersionId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WftwFilterState &&
          runtimeType == other.runtimeType &&
          activeVersionId == other.activeVersionId &&
          fontSizeScale == other.fontSizeScale &&
          activeFontFamily == other.activeFontFamily &&
          textColorHex == other.textColorHex &&
          isBold == other.isBold &&
          isItalic == other.isItalic &&
          textAlign == other.textAlign &&
          backgroundPreset == other.backgroundPreset &&
          yearFilter == other.yearFilter &&
          bookFilter == other.bookFilter &&
          sortBy == other.sortBy &&
          comparisonVersionId == other.comparisonVersionId;

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
        yearFilter,
        bookFilter,
        sortBy,
        comparisonVersionId,
      );
}
