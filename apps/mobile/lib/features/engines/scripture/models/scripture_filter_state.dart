import 'package:mobile/core/engines/base_feed_engine.dart';

class ScriptureFilterState extends BaseFeedFilterState {
  final String activeVersionId;
  final double fontSizeScale;
  final String activeFontFamily;

  const ScriptureFilterState({
    this.activeVersionId = 'WEB',
    this.fontSizeScale = 1.0,
    this.activeFontFamily = 'Playfair',
  });

  ScriptureFilterState copyWith({
    String? activeVersionId,
    double? fontSizeScale,
    String? activeFontFamily,
  }) {
    return ScriptureFilterState(
      activeVersionId: activeVersionId ?? this.activeVersionId,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      activeFontFamily: activeFontFamily ?? this.activeFontFamily,
    );
  }
}
