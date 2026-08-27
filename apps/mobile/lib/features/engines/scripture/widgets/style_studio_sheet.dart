import 'package:flutter/material.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';

class StyleStudioSheet extends StatefulWidget {
  final ScriptureCard card;
  final ScriptureFilterState filterState;
  final ValueChanged<ScriptureFilterState> onFilterChanged;
  final VoidCallback onRefreshCard;

  const StyleStudioSheet({
    super.key,
    required this.card,
    required this.filterState,
    required this.onFilterChanged,
    required this.onRefreshCard,
  });

  @override
  State<StyleStudioSheet> createState() => _StyleStudioSheetState();
}

class _StyleStudioSheetState extends State<StyleStudioSheet> {
  late double _fontSizeScale;
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _fontSizeScale = widget.filterState.fontSizeScale;
    _fontFamily = widget.card.customFontFamily ?? widget.filterState.activeFontFamily;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Customize Style',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Font Family Picker
          const Text(
            'TYPOGRAPHY FONT',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFontChip('Playfair', 'Classic Serif'),
                _buildFontChip('Cinzel', 'Monumental'),
                _buildFontChip('Cormorant', 'Literary'),
                _buildFontChip('Outfit', 'Modern Sans'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Font Size Slider
          const Text(
            'TEXT SIZE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          Row(
            children: [
              const Text(
                'A⁻',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFF59E0B),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFFF59E0B),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _fontSizeScale,
                    min: 0.80,
                    max: 1.35,
                    divisions: 11,
                    onChanged: (val) {
                      setState(() => _fontSizeScale = val);
                      widget.onFilterChanged(
                        widget.filterState.copyWith(fontSizeScale: val),
                      );
                    },
                  ),
                ),
              ),
              const Text(
                'A⁺',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Background Theme Wallpapers
          const Text(
            'BACKGROUND THEME',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: ScriptureThemeCatalog.presets.length,
              itemBuilder: (context, index) {
                final preset = ScriptureThemeCatalog.presets[index];
                final isSelected = widget.card.activeBackground == preset.id;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      widget.card.customBackgroundPreset = preset.id;
                    });
                    widget.onRefreshCard();
                  },
                  child: Container(
                    width: 72,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFF59E0B)
                            : Colors.white12,
                        width: isSelected ? 2.2 : 1.0,
                      ),
                      gradient: preset.isGradient && preset.gradientColors != null
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: preset.gradientColors!,
                            )
                          : null,
                      color: const Color(0xFF0F172A),
                    ),
                    child: Stack(
                      children: [
                        if (isSelected)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              Icons.check_circle,
                              color: Color(0xFFF59E0B),
                              size: 14,
                            ),
                          ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(
                              preset.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
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
    );
  }

  Widget _buildFontChip(String id, String label) {
    final isSelected = _fontFamily == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text('$label ($id)'),
        selected: isSelected,
        selectedColor: const Color(0xFFF59E0B).withOpacity(0.25),
        backgroundColor: Colors.white10,
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFFF59E0B) : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFFF59E0B) : Colors.transparent,
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() => _fontFamily = id);
            widget.card.customFontFamily = id;
            widget.onFilterChanged(
              widget.filterState.copyWith(activeFontFamily: id),
            );
            widget.onRefreshCard();
          }
        },
      ),
    );
  }
}
