import 'package:mobile/core/engines/base_feed_engine.dart';

class ScriptureFilterState extends BaseFeedFilterState {
  final String activeVersionId;
  final double fontSizeScale;
  final String activeFontFamily;
  final String textColorHex;
  final bool isBold;
  final bool isItalic;
  final String textAlign; // 'left', 'center', 'right'

  const ScriptureFilterState({
    this.activeVersionId = 'WEB',
    this.fontSizeScale = 1.0,
    this.activeFontFamily = 'Playfair',
    this.textColorHex = '#FFFFFF',
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = 'center',
  });

  ScriptureFilterState copyWith({
    String? activeVersionId,
    double? fontSizeScale,
    String? activeFontFamily,
    String? textColorHex,
    bool? isBold,
    bool? isItalic,
    String? textAlign,
  }) {
    return ScriptureFilterState(
      activeVersionId: activeVersionId ?? this.activeVersionId,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      activeFontFamily: activeFontFamily ?? this.activeFontFamily,
      textColorHex: textColorHex ?? this.textColorHex,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      textAlign: textAlign ?? this.textAlign,
    );
  }
}
