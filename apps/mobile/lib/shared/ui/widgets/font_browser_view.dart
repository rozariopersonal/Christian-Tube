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
  String _selectedCategory = 'all'; // 'all', 'reading', 'display'

  @override
  void initState() {
    super.initState();
    // Progressive Auto-Preview: stream active language fonts in parallel
    if (!_isTestEnvironment) {
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
    final lang = widget.appearance.languageCode;
    final fonts = ScriptureThemeCatalog.getFontsForLanguage(lang);
    for (final font in fonts) {
      final family = ScriptureThemeCatalog.resolveFontFamily(
        font.id,
        font.languageCode ?? lang,
      );
      if (family != null) {
        unawaited(ReaderFontsService.instance.ensureFamily(family));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = widget.appearance.textColor(tokens);
    final borderCol = widget.appearance.surfaceBorder(tokens);
    final screen = ScreenClass.of(context);

    final fonts = ScriptureThemeCatalog.getFontsForLanguage(widget.appearance.languageCode);
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

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All Fonts', 'all', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('📖 Long-Form Reading', 'reading', tokens),
              const SizedBox(width: 8),
              _buildFilterChip('🎨 Stylish Display', 'display', tokens),
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
                    languageCode: widget.appearance.languageCode,
                    isSelected: isSelected,
                    appearance: widget.appearance,
                    onSelect: () {
                      widget.appearance.fontFamily = font.id;
                      final family = ScriptureThemeCatalog.resolveFontFamily(
                        font.id,
                        font.languageCode ?? widget.appearance.languageCode,
                      );
                      if (family != null) {
                        ReaderFontsService.instance.ensureFamily(family);
                      }
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
    if (_selectedCategory == 'reading') {
      // Return reading-friendly body fonts (Serif & Clean Sans)
      return allFonts.where((f) {
        final sub = f.subtitle.toLowerCase();
        return sub.contains('serif') ||
            sub.contains('clean') ||
            sub.contains('reading') ||
            sub.contains('literature') ||
            sub.contains('contemporary');
      }).toList();
    }
    if (_selectedCategory == 'display') {
      // Return stylish display fonts (Script, Calligraphy, Bold Display)
      return allFonts.where((f) {
        final sub = f.subtitle.toLowerCase();
        return sub.contains('script') ||
            sub.contains('calligraphy') ||
            sub.contains('display') ||
            sub.contains('roman') ||
            sub.contains('monumental') ||
            sub.contains('devotional') ||
            sub.contains('rounded');
      }).toList();
    }
    return allFonts;
  }
}
