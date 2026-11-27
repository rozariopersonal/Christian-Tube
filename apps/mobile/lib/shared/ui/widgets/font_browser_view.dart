import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';
import 'font_specimen_card.dart';

/// Level 2 Apple Books drill-down font browser with progressive auto-preview.
class FontBrowserView extends StatefulWidget {
  final ReaderAppearance appearance;
  final VoidCallback onBack;
  final VoidCallback? onFontSelected;

  const FontBrowserView({
    super.key,
    required this.appearance,
    required this.onBack,
    this.onFontSelected,
  });

  @override
  State<FontBrowserView> createState() => _FontBrowserViewState();
}

class _FontBrowserViewState extends State<FontBrowserView> {
  String _selectedCategory = 'all'; // 'all', 'serif', 'sans', 'display', 'handwriting', 'mono'
  late String _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.appearance.languageCode;
    // Progressive Auto-Preview: load remote catalog & stream active language fonts
    if (!_isTestEnvironment) {
      unawaited(ReaderFontsService.instance.loadCatalog().then((_) {
        if (mounted) {
          _prefetchActiveLanguageFonts();
          setState(() {});
        }
      }));
      _prefetchActiveLanguageFonts();
    }
  }

  bool get _isTestEnvironment {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  void _prefetchActiveLanguageFonts() {
    final lang = _selectedLanguage;
    final fonts = ScriptureThemeCatalog.getFontsForLanguage(lang).take(8);
    for (final font in fonts) {
      final family = ScriptureThemeCatalog.resolveFontFamily(
        font.id,
        font.languageCode ?? lang,
      );
      if (family != null) {
        unawaited(ReaderFontsService.instance.ensureResolved(font.id, font.languageCode ?? lang));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = widget.appearance.textColor(tokens);
    final borderCol = widget.appearance.surfaceBorder(tokens);
    final screen = ScreenClass.of(context);

    final catalog = ReaderFontsService.instance.catalog;
    final fonts = ScriptureThemeCatalog.getFontsForLanguage(_selectedLanguage);
    final filteredFonts = _filterFonts(fonts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Back navigation and Title
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onBack,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 24, color: textCol),
                    const SizedBox(width: 2),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: textCol,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Typography',
                style: TextStyle(
                  color: textCol,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderCol),
              ),
              child: Text(
                widget.appearance.languageCode.toUpperCase(),
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!screen.isCompact) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: widget.appearance.mutedTextColor(tokens)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),

        // Language Filter Chips (when remote catalog is loaded)
        if (catalog != null && catalog.languages.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildLanguageChip('All', 'all', tokens),
                for (final lang in catalog.languages) ...[
                  const SizedBox(width: 6),
                  _buildLanguageChip(
                    lang.code == 'en' ? 'EN' : lang.nativeLabel,
                    lang.code,
                    tokens,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All', 'all', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('Serif', 'serif', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('Sans', 'sans', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('Display', 'display', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('Script', 'handwriting', tokens),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Specimen List with instant reactive selection
        Expanded(
          child: ListenableBuilder(
            listenable: widget.appearance,
            builder: (context, _) {
              return ListView.separated(
                itemCount: filteredFonts.length,
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                physics: const BouncingScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final font = filteredFonts[index];
                  final isSelected = font.id == widget.appearance.fontFamily;

                  return FontSpecimenCard(
                    fontOption: font,
                    languageCode: font.languageCode ?? _selectedLanguage,
                    isSelected: isSelected,
                    appearance: widget.appearance,
                    onSelect: () {
                      widget.appearance.fontFamily = font.id;
                      unawaited(ReaderFontsService.instance.ensureResolved(
                        font.id,
                        font.languageCode ?? _selectedLanguage,
                      ));
                      setState(() {});
                      widget.onFontSelected?.call();
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageChip(String label, String langCode, AppTokens tokens) {
    final normSelected = ReaderFontsService.instance.catalog?.normalizeLanguage(_selectedLanguage) ?? _selectedLanguage;
    final isSelected = normSelected == langCode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedLanguage = langCode);
        if (!_isTestEnvironment) {
          _prefetchActiveLanguageFonts();
        }
      },
      selectedColor: tokens.accent.withValues(alpha: 0.22),
      backgroundColor: tokens.surfaceVariant,
      labelStyle: TextStyle(
        color: isSelected ? tokens.accent : tokens.onSurface,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? tokens.accent : tokens.surfaceBorder,
        width: isSelected ? 1.2 : 0.8,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildFilterChip(String label, String categoryId, AppTokens tokens) {
    final isSelected = _selectedCategory == categoryId;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedCategory = categoryId),
      selectedColor: tokens.accent.withValues(alpha: 0.22),
      backgroundColor: tokens.surfaceVariant,
      labelStyle: TextStyle(
        color: isSelected ? tokens.accent : tokens.onSurface,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? tokens.accent : tokens.surfaceBorder,
        width: isSelected ? 1.2 : 0.8,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  List<ScriptureFontOption> _filterFonts(List<ScriptureFontOption> allFonts) {
    if (_selectedCategory == 'all') return allFonts;
    return allFonts.where((f) {
      if (f.category != null && f.category!.isNotEmpty) {
        return f.category == _selectedCategory;
      }
      final sub = f.subtitle.toLowerCase();
      switch (_selectedCategory) {
        case 'serif':
          return sub.contains('serif') || sub.contains('literature') || sub.contains('editorial');
        case 'sans':
          return sub.contains('sans') || sub.contains('clean') || sub.contains('contemporary') || sub.contains('modern');
        case 'display':
          return sub.contains('display') || sub.contains('roman') || sub.contains('monumental') || sub.contains('rounded');
        case 'handwriting':
          return sub.contains('script') || sub.contains('handwritten') || sub.contains('calligraphy') || sub.contains('devotional');
        default:
          return true;
      }
    }).toList();
  }
}
