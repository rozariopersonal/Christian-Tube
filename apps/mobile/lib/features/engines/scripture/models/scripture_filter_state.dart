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

  const ScriptureFilterState({
    this.activeVersionId = 'WEB',
    this.fontSizeScale = 1.0,
    this.activeFontFamily = 'Playfair',
    this.textColorHex = '#FFFFFF',
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = 'center',
    this.backgroundPreset = 'mountain_dawn',
  });

  ScriptureFilterState copyWith({
    String? activeVersionId,
    double? fontSizeScale,
    String? activeFontFamily,
    String? textColorHex,
    bool? isBold,
    bool? isItalic,
    String? textAlign,
    String? backgroundPreset,
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
          backgroundPreset == other.backgroundPreset;

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
      );
}
