import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/glossary_entry.dart';
import '../services/dictionary_download_manager.dart';
import '../services/glossary_service.dart';

/// Modal bottom sheet (on compact) or centered dialog (on medium/expanded)
/// displaying the complete 17-field classical biblical glossary definition.
class GlossaryEntrySheet extends StatefulWidget {
  final String word;
  final GlossaryEntry? initialEntry;
  final int? book;
  final int? chapter;
  final int? verse;

  const GlossaryEntrySheet({
    super.key,
    required this.word,
    this.initialEntry,
    this.book,
    this.chapter,
    this.verse,
  });

  /// Presents the glossary entry popup for [word].
  static Future<void> show(
    BuildContext context, {
    required String word,
    GlossaryEntry? initialEntry,
    int? book,
    int? chapter,
    int? verse,
  }) async {
    final screen = ScreenClass.of(context);
    if (screen.isCompact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => GlossaryEntrySheet(
          word: word,
          initialEntry: initialEntry,
          book: book,
          chapter: chapter,
          verse: verse,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
            child: GlossaryEntrySheet(
              word: word,
              initialEntry: initialEntry,
              book: book,
              chapter: chapter,
              verse: verse,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<GlossaryEntrySheet> createState() => _GlossaryEntrySheetState();
}

class _GlossaryEntrySheetState extends State<GlossaryEntrySheet> {
  final GlossaryService _glossaryService = GlossaryService();
  final DictionaryDownloadManager _downloadManager = DictionaryDownloadManager();

  GlossaryEntry? _entry;
  bool _isLoading = true;
  bool _isDbInstalled = false;
  late String _currentWord;

  @override
  void initState() {
    super.initState();
    _currentWord = widget.word;
    _entry = widget.initialEntry;
    _isDbInstalled = widget.initialEntry != null;
    _isLoading = widget.initialEntry == null;
    _downloadManager.addListener(_onDownloadProgress);
    if (_entry == null) {
      _loadEntry(_currentWord);
    }
  }

  @override
  void dispose() {
    _downloadManager.removeListener(_onDownloadProgress);
    super.dispose();
  }

  void _onDownloadProgress() {
    if (!mounted) return;
    setState(() {});
    if (_downloadManager.isInstalled('ta_glossary') && _entry == null && !_isLoading) {
      _loadEntry(_currentWord);
    }
  }

  Future<void> _loadEntry(String query) async {
    setState(() {
      _isLoading = true;
      _currentWord = query;
    });

    try {
      final installed = await _glossaryService.isInstalled();
      final result = await _glossaryService.lookup(
        query,
        book: widget.book,
        chapter: widget.chapter,
        verse: widget.verse,
      );

      if (mounted) {
        setState(() {
          _isDbInstalled = installed || result != null;
          _entry = result;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final screen = ScreenClass.of(context);

    final content = Material(
      color: tokens.surface,
      borderRadius: screen.isCompact
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag Handle & Close Bar
            _buildTopBar(context, tokens, screen),

            // Main Scrollable Content
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : (!_isDbInstalled)
                      ? _buildDownloadPrompt(tokens, theme)
                      : (_entry == null)
                          ? _buildNotFound(tokens, theme)
                          : _buildEntryBody(context, tokens, theme, _entry!),
            ),
          ],
        ),
      ),
    );

    if (screen.isCompact) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildTopBar(BuildContext context, AppTokens tokens, ScreenClass screen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (screen.isCompact) ...[
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'வேதாகம சொல்லகராதி',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurfaceMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                splashRadius: 20,
                icon: Icon(Icons.close_rounded, size: 20, color: tokens.onSurfaceMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.surfaceBorder),
      ],
    );
  }

  Widget _buildDownloadPrompt(AppTokens tokens, ThemeData theme) {
    final isDownloading = _downloadManager.isDownloading('ta_glossary');
    final progress = _downloadManager.getProgress('ta_glossary');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_download_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'வேதாகம சொல்லகராதி தேவை',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'முழுமையான 17,200+ மூல மொழி கிரேக்க/எபிரெய விளக்கங்கள் மற்றும் வசன பயன்பாடுகளைப் பார்க்க சொல்லகராதியைத் தரவிறக்கம் செய்யவும்.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: tokens.onSurfaceMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'தரவிறக்கம் செய்யப்படுகிறது... ${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
          ] else
            FilledButton.icon(
              onPressed: () async {
                await _downloadManager.downloadDictionary('ta_glossary');
                await _loadEntry(_currentWord);
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('சொல்லகராதி தரவிறக்கு (14.6 MB)'),
            ),
        ],
      ),
    );
  }

  Widget _buildNotFound(AppTokens tokens, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: tokens.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              'சொல் கிடைக்கவில்லை',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: tokens.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              '"$_currentWord" சொல்லுக்குரிய வேதாகம விளக்கம் அகராதியில் காணப்படவில்லை.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: tokens.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryBody(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
    GlossaryEntry entry,
  ) {
    final primaryColor = theme.colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HERO HEADWORD & PHONETICS
          Text(
            entry.headword,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Transliteration, POS, Category badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (entry.transliteration.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Text(
                    entry.transliteration,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${entry.posTa} • ${entry.pos}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
              if (entry.category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tokens.onSurfaceMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // English Gloss
          Text(
            '"${entry.glossEn}"',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              color: primaryColor,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // 2. ORIGINAL LANGUAGE ROOT BANNER (Hebrew/Greek & Strong's)
          if (entry.originalLemma != null && entry.originalLemma!.isNotEmpty)
            _buildOriginalRootBanner(tokens, theme, entry),

          const SizedBox(height: 18),

          // 3. TAMIL THEOLOGICAL DEFINITION
          _buildSectionHeader('வேதாகம விளக்கம்', Icons.menu_book_rounded, tokens, theme),
          const SizedBox(height: 6),
          Text(
            entry.definitionTa,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.6,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // 4. ENGLISH EXPOSITORY DEFINITION
          _buildSectionHeader('English Expository Definition', Icons.translate_rounded, tokens, theme),
          const SizedBox(height: 6),
          Text(
            entry.definitionEn,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: tokens.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 18),

          // 5. MODERN USAGE (நவீன பயன்பாடு)
          if (entry.modernEquivalents.isNotEmpty) ...[
            _buildSectionHeader('நவீன பயன்பாட்டுச் சொற்கள்', Icons.alt_route_rounded, tokens, theme),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: entry.modernEquivalents.map((modern) {
                return Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tokens.surfaceVariant,
                  side: BorderSide(color: tokens.surfaceBorder),
                  label: Text(
                    modern,
                    style: TextStyle(fontSize: 13, color: tokens.onSurface),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
          ],

          // 6. BIBLICAL INFLECTIONS (வேதாகம வடிவங்கள்)
          if (entry.forms.isNotEmpty) ...[
            _buildSectionHeader('வேதாகம பயன்பாட்டு வடிவங்கள்', Icons.grain_rounded, tokens, theme),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.forms.map((form) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.surfaceBorder.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    form,
                    style: TextStyle(fontSize: 12.5, color: tokens.onSurfaceMuted),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
          ],

          // 7. NOTES & CLASSICAL CONTEXT
          if (entry.notes.isNotEmpty) ...[
            _buildSectionHeader('ஆவிக்குரிய குறிப்பு', Icons.info_outline_rounded, tokens, theme),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Text(
                entry.notes,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: tokens.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 8. SCRIPTURE EXAMPLES (Vertical Stack — Never Side-by-Side)
          if (entry.examples.isNotEmpty) ...[
            _buildSectionHeader('வேதாகம உதாரணங்கள்', Icons.format_quote_rounded, tokens, theme),
            const SizedBox(height: 10),
            Column(
              children: entry.examples.map((ex) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${ex.sentenceTa}”',
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                          color: tokens.onSurface,
                        ),
                      ),
                      if (ex.sentenceEn.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          ex.sentenceEn,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            fontStyle: FontStyle.italic,
                            color: tokens.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // 9. RELATED TERMS (Clean Chips — No 'See' Clutter)
          if (entry.seeAlso.isNotEmpty) ...[
            _buildSectionHeader('தொடர்புடைய சொற்கள்', Icons.hub_rounded, tokens, theme),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.seeAlso.map((rel) {
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tokens.surfaceVariant,
                  side: BorderSide(color: tokens.surfaceBorder),
                  avatar: Icon(Icons.arrow_forward_rounded, size: 14, color: primaryColor),
                  label: Text(
                    rel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: tokens.onSurface,
                    ),
                  ),
                  onPressed: () => _loadEntry(rel),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // 10. OCCURRENCE COUNT FOOTER
          if (entry.occurrenceCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_rounded, size: 17, color: primaryColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'வேதாகமத்தில் ${entry.occurrenceCount} இடங்களில் வருகிறது',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    AppTokens tokens,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.onSurfaceMuted,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOriginalRootBanner(
    AppTokens tokens,
    ThemeData theme,
    GlossaryEntry entry,
  ) {
    final isHebrew = (entry.originalLang?.toLowerCase() ?? '') == 'hebrew';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'மூல மொழி பதம் (${entry.originalLang ?? "Root"})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.onSurfaceMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (entry.strongs != null && entry.strongs!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Strong\'s ${entry.strongs}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                entry.originalLemma!,
                textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: tokens.onSurface,
                ),
              ),
              if (entry.originalTranslit != null && entry.originalTranslit!.isNotEmpty)
                Text(
                  '(${entry.originalTranslit})',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: tokens.onSurfaceMuted,
                  ),
                ),
            ],
          ),
          if (entry.rootDefinitionTa != null && entry.rootDefinitionTa!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.rootDefinitionTa!,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: tokens.onSurface,
              ),
            ),
          ],
          if (entry.rootDefinitionEn != null && entry.rootDefinitionEn!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.rootDefinitionEn!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
          if (entry.originalContext != null && entry.originalContext!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'பயன்பாடு: ${entry.originalContext!}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
