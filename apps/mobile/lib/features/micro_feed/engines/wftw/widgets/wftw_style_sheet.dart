import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import '../models/wftw_card.dart';
import '../models/wftw_filter_state.dart';

class WftwStyleSheet extends StatefulWidget {
  final WftwCard card;
  final WftwFilterState filterState;
  final ValueChanged<WftwFilterState> onFilterChanged;
  final VoidCallback onRefreshCard;

  const WftwStyleSheet({
    super.key,
    required this.card,
    required this.filterState,
    required this.onFilterChanged,
    required this.onRefreshCard,
  });

  @override
  State<WftwStyleSheet> createState() => _WftwStyleSheetState();
}

class _WftwStyleSheetState extends State<WftwStyleSheet> {
  late double _fontSizeScale;
  late String _fontFamily;
  late String _backgroundPresetId;
  late String _textAlign;

  @override
  void initState() {
    super.initState();
    _fontSizeScale = widget.filterState.fontSizeScale;
    _fontFamily = widget.filterState.activeFontFamily;
    _backgroundPresetId = widget.card.activeBackground;
    _textAlign = widget.filterState.textAlign;
  }

  void _applyLiveChange() {
    widget.card.customBackgroundPreset = _backgroundPresetId;
    final newState = widget.filterState.copyWith(
      fontSizeScale: _fontSizeScale,
      activeFontFamily: _fontFamily,
      backgroundPreset: _backgroundPresetId,
      textAlign: _textAlign,
    );
    widget.onFilterChanged(newState);
    widget.onRefreshCard();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.onSurfaceDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Card Appearance',
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Font Size Scale
                  Text(
                    'FONT SIZE',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.text_fields_rounded, size: 16, color: tokens.onSurfaceMuted),
                      Expanded(
                        child: Slider(
                          value: _fontSizeScale,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          activeColor: tokens.accent,
                          inactiveColor: tokens.surfaceBorder,
                          onChanged: (val) {
                            setState(() => _fontSizeScale = val);
                            _applyLiveChange();
                          },
                        ),
                      ),
                      Icon(Icons.text_fields_rounded, size: 24, color: tokens.onSurface),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Text Alignment
                  Text(
                    'ALIGNMENT',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left_rounded)),
                      ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center_rounded)),
                      ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right_rounded)),
                    ],
                    selected: {_textAlign},
                    onSelectionChanged: (set) {
                      setState(() => _textAlign = set.first);
                      _applyLiveChange();
                    },
                  ),
                  const SizedBox(height: 20),

                  // Background Preset
                  Text(
                    'BACKGROUND THEME',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ScriptureThemeCatalog.presets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, idx) {
                        final preset = ScriptureThemeCatalog.presets[idx];
                        final isSelected = _backgroundPresetId == preset.id;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _backgroundPresetId = preset.id);
                            _applyLiveChange();
                          },
                          child: Container(
                            width: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? tokens.accent : tokens.surfaceBorder,
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (preset.imageUrl != null)
                                  CachedNetworkImage(
                                    imageUrl: preset.imageUrl!,
                                    fit: BoxFit.cover,
                                  )
                                else if (preset.gradientColors != null)
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: preset.gradientColors!,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                  ),
                                if (isSelected)
                                  Center(
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      color: tokens.accent,
                                      size: 24,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
