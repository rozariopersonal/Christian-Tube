import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/layout/adaptive_sheet_frame.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/link/deep_link_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../bible/models/bible_reference.dart';
import '../../../bible/services/bible_passage_navigator.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';
import '../services/saved_scripture_service.dart';
import '../services/scripture_image_exporter.dart';
import 'compare_version_picker_sheet.dart';

class VerseActionAppearanceSheet extends StatefulWidget {
  final ScriptureCard card;
  final ScriptureFilterState filterState;
  final ValueChanged<ScriptureFilterState> onFilterChanged;
  final VoidCallback onRefreshCard;
  final GlobalKey? repaintBoundaryKey;

  const VerseActionAppearanceSheet({
    super.key,
    required this.card,
    required this.filterState,
    required this.onFilterChanged,
    required this.onRefreshCard,
    this.repaintBoundaryKey,
  });

  @override
  State<VerseActionAppearanceSheet> createState() =>
      _VerseActionAppearanceSheetState();
}

class _VerseActionAppearanceSheetState extends State<VerseActionAppearanceSheet> {
  late double _fontSizeScale;
  late String _fontFamily;
  late String _textColorHex;
  late bool _isBold;
  late bool _isItalic;
  late String _textAlign;
  late String _backgroundPresetId;
  bool _isSaved = false;
  bool _applyToAll = false;

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
    _isSaved = widget.card.isSaved;
  }

  void _applyLiveChange() {
    widget.card.customBackgroundPreset =
        _applyToAll ? null : _backgroundPresetId;
    widget.card.customFontFamily = _applyToAll ? null : _fontFamily;

    final newState = widget.filterState.copyWith(
      fontSizeScale: _fontSizeScale,
      activeFontFamily: _fontFamily,
      textColorHex: _textColorHex,
      isBold: _isBold,
      isItalic: _isItalic,
      textAlign: _textAlign,
      backgroundPreset: _applyToAll
          ? _backgroundPresetId
          : widget.filterState.backgroundPreset,
    );

    widget.onFilterChanged(newState);
    widget.onRefreshCard();
  }

  Future<void> _shareStory() async {
    final key = widget.repaintBoundaryKey ?? GlobalKey();
    await ScriptureImageExporter.captureAndShare(
      context: context,
      boundaryKey: key,
      card: widget.card,
      activeVersionId: widget.filterState.activeVersionId,
      fontFamily: _fontFamily,
      fontSizeScale: _fontSizeScale,
      textColorHex: _textColorHex,
      isBold: _isBold,
      isItalic: _isItalic,
      textAlign: _textAlign,
      accentColor: context.accent,
    );
  }

  Future<void> _copyText() async {
    final tokens = context.tokens;
    final link = DeepLinkService.bible(
      book: widget.card.bookName,
      chapter: widget.card.chapter,
      verse: widget.card.startVerse,
    );
    final text =
        '“${widget.card.resolvedText ?? ""}”\n\n— ${widget.card.referenceLabel} (${widget.card.resolvedVersion ?? widget.filterState.activeVersionId})\n\n$link';
    await Clipboard.setData(ClipboardData(text: text));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scripture copied to clipboard!',
            style: TextStyle(color: tokens.onSurface),
          ),
          backgroundColor: tokens.surfaceElevated,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleBookmark() async {
    final tokens = context.tokens;
    final isNowSaved = await SavedScriptureService().toggleSave(
      widget.card,
      widget.filterState.activeVersionId,
    );
    setState(() {
      _isSaved = isNowSaved;
      widget.card.isSaved = isNowSaved;
    });
    widget.onRefreshCard();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNowSaved
                ? 'Saved ${widget.card.referenceLabel} to bookmarks!'
                : 'Removed from bookmarks',
            style: TextStyle(color: tokens.onSurface),
          ),
          backgroundColor: tokens.surfaceElevated,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openCompare() {
    showAdaptiveBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => CompareVersionPickerSheet(
        activeVersionId: widget.filterState.activeVersionId,
        currentComparisonId: widget.filterState.comparisonVersionId,
        onSelectComparison: (comparisonId) {
          final newState = widget.filterState.copyWith(
            comparisonVersionId: comparisonId,
            clearComparisonVersion: comparisonId == null,
          );
          widget.onFilterChanged(newState);
        },
      ),
    );
  }

  void _openInReader() {
    final versionId = widget.card.resolvedVersion ?? widget.filterState.activeVersionId;
    int bookNumber = widget.card.bookNumber;
    int chapter = widget.card.chapter;
    int verse = widget.card.startVerse;

    final mapping = widget.card.verseMappings?[versionId];
    if (mapping is Map) {
      bookNumber = mapping['bookNumber'] ?? bookNumber;
      chapter = mapping['chapter'] ?? chapter;
      verse = mapping['startVerse'] ?? verse;
    }

    final nav = Navigator.of(context);
    nav.pop(); // Dismiss sheet first

    BiblePassageNavigator.instance.navigateTo(
      BibleReference(
        bookNumber: bookNumber,
        chapter: chapter,
        verse: verse,
        versionId: versionId,
      ),
      context: nav.context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final versionMeta = BibleDownloadManager.getMeta(
        widget.card.resolvedVersion ?? widget.filterState.activeVersionId);
    final activePreset = ScriptureThemeCatalog.getPreset(_backgroundPresetId);

    return AdaptiveSheetFrame(
      maxHeightFactor: 0.88,
      maxWidth: kSheetMaxWidth,
      showDragHandle: false,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
                        decoration: BoxDecoration(
                          color: tokens.onSurfaceDisabled.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Header Row: Reference & Close
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: tokens.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: _openInReader,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${widget.card.referenceLabel} • ${widget.card.resolvedVersion ?? widget.filterState.activeVersionId}',
                                      style: TextStyle(
                                        color: tokens.onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: tokens.onSurfaceMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 20, color: tokens.onSurfaceMuted),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 3. Row 1: Primary Action Items (Share, Copy, Bookmark, Compare, Read)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tokens.surfaceBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ActionItem(
                            icon: Icons.ios_share_rounded,
                            label: 'Share Story',
                            onTap: _shareStory,
                            tokens: tokens,
                          ),
                          _ActionItem(
                            icon: Icons.copy_rounded,
                            label: 'Copy Text',
                            onTap: _copyText,
                            tokens: tokens,
                          ),
                          _ActionItem(
                            icon: _isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: _isSaved ? 'Saved' : 'Bookmark',
                            iconColor: _isSaved ? tokens.accent : null,
                            onTap: _toggleBookmark,
                            tokens: tokens,
                          ),
                          _ActionItem(
                            icon: Icons.compare_arrows_rounded,
                            label: widget.filterState.comparisonVersionId ?? 'Compare',
                            iconColor: widget.filterState.comparisonVersionId != null
                                ? tokens.accent
                                : null,
                            onTap: _openCompare,
                            tokens: tokens,
                          ),
                          _ActionItem(
                            icon: Icons.menu_book_rounded,
                            label: 'Read Chapter',
                            onTap: _openInReader,
                            tokens: tokens,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(color: tokens.surfaceBorder, height: 1),
                    const SizedBox(height: 10),

                    // 4. Scrollable Card Appearance & Styling Studio
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 🎨 Live Mini Preview
                            _buildLivePreviewCard(activePreset, versionMeta, tokens),
                            const SizedBox(height: 16),

                            // A. Wallpapers Carousel
                            _buildSectionLabel('BACKGROUND THEME', tokens),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 76,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: ScriptureThemeCatalog.presets.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final p = ScriptureThemeCatalog.presets[index];
                                  final isSelected = p.id == _backgroundPresetId;
                                  return _buildWallpaperThumbnail(
                                      p, isSelected, tokens);
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // B. Font Family Selector
                            _buildSectionLabel(
                                'FONT FAMILY (${versionMeta.language.toUpperCase()})',
                                tokens),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 48,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: ScriptureThemeCatalog
                                    .getFontsForLanguage(versionMeta.languageCode)
                                    .length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final fonts =
                                      ScriptureThemeCatalog.getFontsForLanguage(
                                          versionMeta.languageCode);
                                  final font = fonts[index];
                                  final isSelected = font.id == _fontFamily;
                                  return _buildFontChip(
                                      font, isSelected, versionMeta.languageCode, tokens);
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // C. Text Color Swatches
                            _buildSectionLabel('TEXT COLOR', tokens),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: ScriptureThemeCatalog.colorPalette.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final c =
                                      ScriptureThemeCatalog.colorPalette[index];
                                  final isSelected = c.hex == _textColorHex;
                                  return _buildColorDot(c, isSelected, tokens);
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // D. Text Format & Alignment
                            _buildSectionLabel('FORMAT & ALIGNMENT', tokens),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildFormatToggle(
                                  label: 'B',
                                  isBold: true,
                                  isActive: _isBold,
                                  onTap: () {
                                    setState(() => _isBold = !_isBold);
                                    _applyLiveChange();
                                  },
                                  tokens: tokens,
                                ),
                                const SizedBox(width: 8),
                                _buildFormatToggle(
                                  label: 'I',
                                  isItalic: true,
                                  isActive: _isItalic,
                                  onTap: () {
                                    setState(() => _isItalic = !_isItalic);
                                    _applyLiveChange();
                                  },
                                  tokens: tokens,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: tokens.surfaceBorder),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildAlignBtn(
                                            Icons.format_align_left_rounded,
                                            'left',
                                            tokens),
                                        _buildAlignBtn(
                                            Icons.format_align_center_rounded,
                                            'center',
                                            tokens),
                                        _buildAlignBtn(
                                            Icons.format_align_right_rounded,
                                            'right',
                                            tokens),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // E. Font Size Scale Slider
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSectionLabel('TEXT SIZE SCALE', tokens),
                                Text(
                                  '${(_fontSizeScale * 100).toInt()}%',
                                  style: TextStyle(
                                    color: tokens.accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text('A',
                                    style: TextStyle(
                                        color: tokens.onSurfaceMuted,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: tokens.accent,
                                      inactiveTrackColor: tokens.surfaceBorder,
                                      thumbColor: tokens.accent,
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
                                Text('A',
                                    style: TextStyle(
                                        color: tokens.onSurface,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // F. Scope Control Toggle
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: tokens.surfaceVariant,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: tokens.surfaceBorder),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildScopeOption(
                                      title: 'This Verse Only',
                                      isSelected: !_applyToAll,
                                      onTap: () =>
                                          setState(() => _applyToAll = false),
                                      tokens: tokens,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildScopeOption(
                                      title: 'Default for All Verses',
                                      isSelected: _applyToAll,
                                      onTap: () {
                                        setState(() => _applyToAll = true);
                                        _applyLiveChange();
                                      },
                                      tokens: tokens,
                                    ),
                                  ),
                                ],
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

  Widget _buildSectionLabel(String label, AppTokens tokens) {
    return Text(
      label,
      style: TextStyle(
        color: tokens.onSurfaceMuted,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _buildLivePreviewCard(
      BackgroundPreset preset, dynamic versionMeta, AppTokens tokens) {
    final previewText = widget.card.resolvedText ??
        '“Peace I leave with you; my peace I give you.”';
    Color textColor = ScriptureThemeCatalog.parseColor(_textColorHex);
    if (!context.isDark && _textColorHex == '#FFFFFF') {
      textColor = preset.resolveTextColor(context);
    }
    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: _fontFamily,
      languageCode: versionMeta.languageCode,
      baseSize: (14.5 * _fontSizeScale).clamp(11.0, 18.0),
      color: textColor,
      fontWeight: _isBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
    );

    final colors = preset.resolveColors(context);

    return Container(
      height: 110,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tokens.accent.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            preset.isGradient
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors,
                      ),
                    ),
                  )
                : Container(
                    color: colors.isNotEmpty ? colors.first : tokens.surface),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  previewText,
                  style: textStyle,
                  textAlign: _textAlign == 'left'
                      ? TextAlign.left
                      : (_textAlign == 'right'
                          ? TextAlign.right
                          : TextAlign.center),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperThumbnail(
      BackgroundPreset preset, bool isSelected, AppTokens tokens) {
    final colors = preset.resolveColors(context);
    return GestureDetector(
      onTap: () {
        setState(() => _backgroundPresetId = preset.id);
        _applyLiveChange();
      },
      child: Container(
        width: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.surfaceBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tokens.accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Column(
            children: [
              Expanded(
                child: preset.isGradient
                    ? Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      )
                    : Container(
                        color: colors.isNotEmpty
                            ? colors.first
                            : tokens.surfaceVariant),
              ),
              Container(
                height: 20,
                color: isSelected
                    ? tokens.accent.withValues(alpha: 0.2)
                    : tokens.surfaceVariant,
                alignment: Alignment.center,
                child: Text(
                  preset.name,
                  style: TextStyle(
                    color: isSelected ? tokens.accent : tokens.onSurface,
                    fontSize: 8.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFontChip(ScriptureFontOption font, bool isSelected,
      String languageCode, AppTokens tokens) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _fontFamily = font.id);
          _applyLiveChange();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.16)
                : tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.surfaceBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            font.name,
            style: ScriptureThemeCatalog.getTextStyle(
              fontFamily: font.id,
              languageCode: languageCode,
              baseSize: 13,
              color: isSelected ? tokens.accent : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot(
      ScriptureColorOption colorOption, bool isSelected, AppTokens tokens) {
    return GestureDetector(
      onTap: () {
        setState(() => _textColorHex = colorOption.hex);
        _applyLiveChange();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorOption.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.surfaceBorder,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tokens.accent.withValues(alpha: 0.35),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 16,
                color: colorOption.hex == '#FFFFFF'
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildFormatToggle({
    required String label,
    bool isBold = false,
    bool isItalic = false,
    required bool isActive,
    required VoidCallback onTap,
    required AppTokens tokens,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 38,
        decoration: BoxDecoration(
          color: isActive
              ? tokens.accent.withValues(alpha: 0.18)
              : tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? tokens.accent : tokens.surfaceBorder,
            width: isActive ? 1.4 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? tokens.accent : tokens.onSurface,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildAlignBtn(IconData icon, String align, AppTokens tokens) {
    final isSelected = _textAlign == align;
    return GestureDetector(
      onTap: () {
        setState(() => _textAlign = align);
        _applyLiveChange();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? tokens.accent.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
        ),
      ),
    );
  }

  Widget _buildScopeOption({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    required AppTokens tokens,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tokens.scrim.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final AppTokens tokens;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.surfaceVariant,
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? tokens.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
