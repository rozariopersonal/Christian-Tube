import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';

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
    _fontFamily = widget.filterState.activeFontFamily;
    _textColorHex = widget.filterState.textColorHex;
    _isBold = widget.filterState.isBold;
    _isItalic = widget.filterState.isItalic;
    _textAlign = widget.filterState.textAlign;
    _backgroundPresetId = widget.card.activeBackground;
  }

  void _applyLiveChange() {
    widget.card.customBackgroundPreset = _backgroundPresetId;
    widget.card.customFontFamily = null;

    final newState = widget.filterState.copyWith(
      fontSizeScale: _fontSizeScale,
      activeFontFamily: _fontFamily,
      textColorHex: _textColorHex,
      isBold: _isBold,
      isItalic: _isItalic,
      textAlign: _textAlign,
      backgroundPreset: _backgroundPresetId,
    );

    widget.onFilterChanged(newState);
    widget.onRefreshCard();
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.88;
    final activePreset = ScriptureThemeCatalog.getPreset(_backgroundPresetId);
    final versionMeta =
        BibleDownloadManager.getMeta(widget.card.resolvedVersion ?? widget.filterState.activeVersionId);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white12, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 24,
              offset: Offset(0, -6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
              const SizedBox(height: 12),

              // Header Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.palette_rounded,
                          color: Color(0xFFF59E0B), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Live Style Studio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 🎨 INTERACTIVE LIVE MINI PREVIEW CARD
              _buildLivePreviewCard(activePreset, versionMeta),
              const SizedBox(height: 18),

              // 1. BACKGROUND THEMES & WALLPAPERS
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
              const SizedBox(height: 20),

              // 2. FONT FAMILY SELECTOR
              _buildSectionHeader('FONT FAMILY (${versionMeta.language.toUpperCase()})'),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ScriptureThemeCatalog.getFontsForLanguage(versionMeta.languageCode).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final fonts = ScriptureThemeCatalog.getFontsForLanguage(versionMeta.languageCode);
                    final font = fonts[index];
                    final isSelected = font.id == _fontFamily;
                    return _buildFontChip(font, isSelected, versionMeta.languageCode);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 3. TEXT COLOR PALETTE
              _buildSectionHeader('TEXT COLOR'),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ScriptureThemeCatalog.colorPalette.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final colorOption =
                        ScriptureThemeCatalog.colorPalette[index];
                    final isSelected = colorOption.hex == _textColorHex;
                    return _buildColorCircle(colorOption, isSelected);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 4. TEXT FORMAT & ALIGNMENT
              _buildSectionHeader('TEXT FORMAT & ALIGNMENT'),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildStyleToggle(
                    label: 'B',
                    isBoldLabel: true,
                    isActive: _isBold,
                    onTap: () {
                      setState(() => _isBold = !_isBold);
                      _applyLiveChange();
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildStyleToggle(
                    label: 'I',
                    isItalicLabel: true,
                    isActive: _isItalic,
                    onTap: () {
                      setState(() => _isItalic = !_isItalic);
                      _applyLiveChange();
                    },
                  ),
                  const SizedBox(width: 16),
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
                          _buildAlignButton(
                              Icons.format_align_left_rounded, 'left'),
                          _buildAlignButton(
                              Icons.format_align_center_rounded, 'center'),
                          _buildAlignButton(
                              Icons.format_align_right_rounded, 'right'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 5. FONT SIZE SCALE SLIDER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader('TEXT SIZE SCALE'),
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
                          fontSize: 13)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFFF59E0B),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFFF59E0B),
                        overlayColor:
                            const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        trackHeight: 3.5,
                      ),
                      child: Slider(
                        value: _fontSizeScale,
                        min: 0.80,
                        max: 1.35,
                        divisions: 11,
                        onChanged: (val) {
                          setState(() => _fontSizeScale = val);
                          _applyLiveChange();
                        },
                      ),
                    ),
                  ),
                  const Text('A⁺',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLivePreviewCard(BackgroundPreset preset, dynamic versionMeta) {
    final previewText = widget.card.resolvedText ??
        '“Peace I leave with you; my peace I give you.”';
    final textColor = ScriptureThemeCatalog.parseColor(_textColorHex);
    final fontWeight = _isBold ? FontWeight.w700 : FontWeight.w400;
    final fontStyle = _isItalic ? FontStyle.italic : FontStyle.normal;

    final TextAlign align;
    switch (_textAlign) {
      case 'left':
        align = TextAlign.left;
        break;
      case 'right':
        align = TextAlign.right;
        break;
      case 'center':
      default:
        align = TextAlign.center;
        break;
    }

    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: _fontFamily,
      languageCode: versionMeta.languageCode,
      baseSize: (15.0 * _fontSizeScale).clamp(11.0, 20.0),
      color: textColor,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

    return Container(
      height: 135,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Layer
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

          // Dark Scrim Overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0xCC000000)],
              ),
            ),
          ),

          // Live Text & Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      previewText,
                      textAlign: align,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle.copyWith(
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    '— ${widget.card.referenceLabel} (${widget.card.resolvedVersion ?? widget.filterState.activeVersionId}) —',
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // "LIVE PREVIEW" Pill Badge
          Positioned(
            top: 6,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.remove_red_eye_rounded,
                      size: 10, color: Colors.black),
                  SizedBox(width: 3),
                  Text(
                    'LIVE PREVIEW',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
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
        });
        _applyLiveChange();
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

            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),

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

  Widget _buildFontChip(
      ScriptureFontOption font, bool isSelected, String languageCode) {
    final previewStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: font.id,
      languageCode: font.languageCode ?? languageCode,
      baseSize: 15,
      color: isSelected ? const Color(0xFFF59E0B) : Colors.white,
      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
    );

    return GestureDetector(
      onTap: () {
        setState(() {
          _fontFamily = font.id;
        });
        _applyLiveChange();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                      : Colors.white10,
                  width: 0.8,
                ),
              ),
              child: Text(
                font.sampleGlyph,
                style: previewStyle.copyWith(
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              font.name,
              style: TextStyle(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
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
        _applyLiveChange();
      },
      child: Container(
        width: 36,
        height: 36,
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
        _applyLiveChange();
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
