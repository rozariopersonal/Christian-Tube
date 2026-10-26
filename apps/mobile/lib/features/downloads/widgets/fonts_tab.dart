import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/downloads/controllers/downloads_controller.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';
import 'package:mobile/shared/ui/widgets/font_specimen_card.dart';

/// Offline Reader Fonts management tab in DownloadsManagerScreen.
class FontsTab extends StatefulWidget {
  final DownloadsController controller;

  const FontsTab({super.key, required this.controller});

  @override
  State<FontsTab> createState() => _FontsTabState();
}

class _FontsTabState extends State<FontsTab> {
  String _selectedLanguage = 'all'; // 'all', 'en', 'tam', 'mal', 'tel', 'hin', 'kan'
  String _selectedCategory = 'all'; // 'all', 'reading', 'display'
  bool _isBatchDownloading = false;

  final List<Map<String, String>> _languages = const [
    {'code': 'all', 'name': 'All Languages'},
    {'code': 'en', 'name': 'English'},
    {'code': 'tam', 'name': 'தமிழ் (Tamil)'},
    {'code': 'mal', 'name': 'മലയാളം (Malayalam)'},
    {'code': 'tel', 'name': 'తెలుగు (Telugu)'},
    {'code': 'hin', 'name': 'हिन्दी (Hindi)'},
    {'code': 'kan', 'name': 'ಕನ್ನಡ (Kannada)'},
  ];

  @override
  void initState() {
    super.initState();
    ReaderFontsService.instance.scanInstalledFonts();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, ReaderFontsService.instance]),
      builder: (context, _) {
        final storage = widget.controller.state.storage;
        final fonts = _collectFilteredFonts();

        return Center(
          child: MaxWidthBox(
            maxWidth: kReadingMaxWidth,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // 1. Storage & Summary Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.font_download_rounded,
                              color: tokens.accent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reader Fonts & Typography',
                                  style: TextStyle(
                                    color: tokens.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${storage.fontsCount} fonts installed (${storage.fontsFormatted} on disk).',
                                  style: TextStyle(
                                    color: tokens.onSurfaceMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Download typefaces to read offline without internet connectivity. High-legibility book serifs for Bible and literature reading, plus expressive styles for card graphic sharing.',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Batch Download Action Row
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 360;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: isCompact ? double.infinity : null,
                                child: FilledButton.icon(
                                  onPressed: _isBatchDownloading
                                      ? null
                                      : () => _downloadBatch(category: 'reading'),
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: const Text(
                                    'Download Reading Fonts (~1.2 MB)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: tokens.accent,
                                    foregroundColor: tokens.background,
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: isCompact ? double.infinity : null,
                                child: OutlinedButton.icon(
                                  onPressed: _isBatchDownloading
                                      ? null
                                      : () => _downloadBatch(category: 'display'),
                                  icon: const Icon(Icons.palette_outlined, size: 16),
                                  label: const Text(
                                    'Download Display Fonts (~1.5 MB)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tokens.accent,
                                    side: BorderSide(color: tokens.accent),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Language Selector Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _languages.map((lang) {
                      final isSelected = _selectedLanguage == lang['code'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(lang['name']!),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedLanguage = lang['code']!),
                          selectedColor: tokens.accent.withValues(alpha: 0.22),
                          backgroundColor: tokens.surfaceVariant,
                          labelStyle: TextStyle(
                            color: isSelected ? tokens.accent : tokens.onSurface,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: isSelected ? tokens.accent : tokens.surfaceBorder,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 10),

                // 3. Category Selector Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('All Categories', 'all', tokens),
                      const SizedBox(width: 8),
                      _buildCategoryChip('📖 Long-Form Reading', 'reading', tokens),
                      const SizedBox(width: 8),
                      _buildCategoryChip('🎨 Stylish Display', 'display', tokens),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 4. Specimen Cards List
                for (final item in fonts) ...[
                  FontSpecimenCard(
                    fontOption: item.option,
                    languageCode: item.languageCode,
                    isManagementMode: true,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryChip(String label, String categoryId, AppTokens tokens) {
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
      ),
    );
  }

  Future<void> _downloadBatch({required String category}) async {
    setState(() => _isBatchDownloading = true);
    try {
      final languages = _selectedLanguage == 'all'
          ? ['en', 'tam', 'mal', 'tel', 'hin', 'kan']
          : [_selectedLanguage];

      final futures = <Future<bool>>[];
      for (final lang in languages) {
        final fonts = ScriptureThemeCatalog.getFontsForLanguage(lang);
        for (final font in fonts) {
          final isReading = _isReadingCategory(font.subtitle);
          if (category == 'reading' && !isReading) continue;
          if (category == 'display' && isReading) continue;

          final family = ScriptureThemeCatalog.resolveFontFamily(
            font.id,
            font.languageCode ?? lang,
          );
          if (family != null) {
            futures.add(ReaderFontsService.instance.ensureFamily(family));
          }
        }
      }
      await Future.wait(futures);
      await widget.controller.refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fonts downloaded successfully for offline use'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchDownloading = false);
    }
  }

  bool _isReadingCategory(String subtitle) {
    final sub = subtitle.toLowerCase();
    return sub.contains('serif') ||
        sub.contains('clean') ||
        sub.contains('reading') ||
        sub.contains('literature') ||
        sub.contains('contemporary');
  }

  List<_FontItem> _collectFilteredFonts() {
    final languages = _selectedLanguage == 'all'
        ? ['en', 'tam', 'mal', 'tel', 'hin', 'kan']
        : [_selectedLanguage];

    final result = <_FontItem>[];
    for (final lang in languages) {
      final options = ScriptureThemeCatalog.getFontsForLanguage(lang);
      for (final opt in options) {
        final isReading = _isReadingCategory(opt.subtitle);
        if (_selectedCategory == 'reading' && !isReading) continue;
        if (_selectedCategory == 'display' && isReading) continue;

        result.add(_FontItem(option: opt, languageCode: lang));
      }
    }
    return result;
  }
}

class _FontItem {
  final ScriptureFontOption option;
  final String languageCode;

  const _FontItem({required this.option, required this.languageCode});
}
