import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  late String _textColorHex;
  late bool _isBold;
  late bool _isItalic;
  late String _textAlign;
  late String _backgroundPresetId;

  @override
  void initState() {
    super.initState();
    _fontSizeScale = widget.filterState.fontSizeScale;
    _fontFamily =
        widget.card.customFontFamily ?? widget.filterState.activeFontFamily;
    _textColorHex = widget.filterState.textColorHex;
    _isBold = widget.filterState.isBold;
    _isItalic = widget.filterState.isItalic;
    _textAlign = widget.filterState.textAlign;
    _backgroundPresetId = widget.card.activeBackground;
  }

  void _applyStateChange() {
    final newState = widget.filterState.copyWith(
      fontSizeScale: _fontSizeScale,
      activeFontFamily: _fontFamily,
      textColorHex: _textColorHex,
      isBold: _isBold,
      isItalic: _isItalic,
      textAlign: _textAlign,
    );
    widget.onFilterChanged(newState);
    widget.onRefreshCard();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.palette_rounded, color: Color(0xFFF59E0B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Style Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. BACKGROUND WALLPAPERS & THEMES
            _buildSectionHeader('BACKGROUND THEME & WALLPAPER'),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ScriptureThemeCatalog.presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final p = ScriptureThemeCatalog.presets[index];
                  final isSelected = p.id == _backgroundPresetId;
                  return _buildBackgroundThumbnail(p, isSelected);
                },
              ),
            ),
            const SizedBox(height: 22),

            // 2. TYPOGRAPHY FONT FAMILY
            _buildSectionHeader('FONT FAMILY'),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ScriptureThemeCatalog.fontOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final font = ScriptureThemeCatalog.fontOptions[index];
                  final isSelected = font.id == _fontFamily;
                  return _buildFontChip(font, isSelected);
                },
              ),
            ),
            const SizedBox(height: 22),

            // 3. TEXT COLOR PALETTE
            _buildSectionHeader('TEXT COLOR'),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ScriptureThemeCatalog.colorPalette.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final colorOption = ScriptureThemeCatalog.colorPalette[index];
                  final isSelected = colorOption.hex == _textColorHex;
                  return _buildColorCircle(colorOption, isSelected);
                },
              ),
            ),
            const SizedBox(height: 22),

            // 4. BASIC TEXT STYLES (BOLD, ITALIC, ALIGNMENT)
            _buildSectionHeader('TEXT FORMAT & ALIGNMENT'),
            const SizedBox(height: 10),
            Row(
              children: [
                // Bold Button
                _buildStyleToggle(
                  label: 'B',
                  isBoldLabel: true,
                  isActive: _isBold,
                  onTap: () {
                    setState(() => _isBold = !_isBold);
                    _applyStateChange();
                  },
                ),
                const SizedBox(width: 10),

                // Italic Button
                _buildStyleToggle(
                  label: 'I',
                  isItalicLabel: true,
                  isActive: _isItalic,
                  onTap: () {
                    setState(() => _isItalic = !_isItalic);
                    _applyStateChange();
                  },
                ),
                const SizedBox(width: 16),

                // Alignment Controls (Left, Center, Right)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildAlignButton(Icons.format_align_left_rounded, 'left'),
                        _buildAlignButton(Icons.format_align_center_rounded, 'center'),
                        _buildAlignButton(Icons.format_align_right_rounded, 'right'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // 5. FONT SIZE SCALE SLIDER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('TEXT SIZE'),
                Text(
                  '${(_fontSizeScale * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('A⁻',
                    style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFF59E0B),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFFF59E0B),
                      overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      trackHeight: 4.0,
                    ),
                    child: Slider(
                      value: _fontSizeScale,
                      min: 0.80,
                      max: 1.35,
                      divisions: 11,
                      onChanged: (val) {
                        setState(() => _fontSizeScale = val);
                        _applyStateChange();
                      },
                    ),
                  ),
                ),
                const Text('A⁺',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildBackgroundThumbnail(BackgroundPreset preset, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _backgroundPresetId = preset.id;
          widget.card.customBackgroundPreset = preset.id;
        });
        _applyStateChange();
      },
      child: Container(
        width: 68,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preset.isGradient && preset.gradientColors != null)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: preset.gradientColors!,
                  ),
                ),
              )
            else if (preset.imageUrl != null)
              CachedNetworkImage(
                imageUrl: preset.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF1E293B)),
              )
            else
              Container(color: const Color(0xFF0F172A)),

            // Gradient scrim on thumbnail for label readability
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),

            // Selection Checkmark
            if (isSelected)
              const Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 8,
                  backgroundColor: Color(0xFFF59E0B),
                  child: Icon(Icons.check, size: 11, color: Colors.black),
                ),
              ),

            // Name Label
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Text(
                preset.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontChip(ScriptureFontOption font, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _fontFamily = font.id;
          widget.card.customFontFamily = font.id;
        });
        _applyStateChange();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            font.name,
            style: TextStyle(
              color: isSelected ? const Color(0xFFF59E0B) : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorCircle(ScriptureColorOption colorOption, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _textColorHex = colorOption.hex;
        });
        _applyStateChange();
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorOption.color,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: colorOption.color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 18,
                color: colorOption.color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildStyleToggle({
    required String label,
    bool isBoldLabel = false,
    bool isItalicLabel = false,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFFF59E0B) : Colors.white12,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFFF59E0B) : Colors.white,
              fontWeight: isBoldLabel ? FontWeight.w900 : FontWeight.w600,
              fontStyle: isItalicLabel ? FontStyle.italic : FontStyle.normal,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlignButton(IconData icon, String alignmentValue) {
    final isSelected = _textAlign == alignmentValue;
    return GestureDetector(
      onTap: () {
        setState(() => _textAlign = alignmentValue);
        _applyStateChange();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.black : Colors.white70,
        ),
      ),
    );
  }
}
