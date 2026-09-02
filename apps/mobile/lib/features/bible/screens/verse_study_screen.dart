import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_scripture_link.dart';
import '../../books/screens/book_reader_screen.dart';
import '../../dictionary/models/dictionary_entry.dart';
import '../../dictionary/services/dictionary_service.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import '../widgets/cross_reference_card.dart';
import 'bible_screen.dart';

/// Dedicated study screen displaying both Cross References and Historical/Cultural
/// Commentaries for a verse in a cohesive, tabbed presentation.
///
/// Responsive per AGENTS.md:
/// - TabBar pinned at the top inside MaxWidthBox, followed by scrollable TabBarView.
/// - The verse appears as the first element in the references tab.
class VerseStudyScreen extends StatefulWidget {
  final String verseText;
  final String verseLabel;
  final String? versionLabel;
  final String? versionId;
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final List<BibleBackgroundNote> commentaryNotes;
  final Future<List<BookScriptureLink>> bookCommentariesFuture;
  final double baseFontSize;
  final int initialTab;
  final void Function(CrossReference)? onTapReference;
  final void Function(int bookNumber, int chapter, int verse)? onTapPassage;

  const VerseStudyScreen({
    super.key,
    required this.verseText,
    required this.verseLabel,
    this.versionLabel,
    this.versionId,
    this.references = const [],
    this.resolvedTexts = const {},
    this.commentaryNotes = const [],
    required this.bookCommentariesFuture,
    required this.baseFontSize,
    this.initialTab = 0,
    this.onTapReference,
    this.onTapPassage,
  });

  @override
  State<VerseStudyScreen> createState() => _VerseStudyScreenState();
}

class _VerseStudyScreenState extends State<VerseStudyScreen> {
  void _openPassage(int bookNumber, int chapter, int verse) {
    if (widget.onTapPassage != null) {
      widget.onTapPassage!(bookNumber, chapter, verse);
      return;
    }
    final targetBook = bookNumber >= 1 &&
            bookNumber <= BookNameService.englishBookNames.length
        ? BookNameService.englishBookNames[bookNumber - 1]
        : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleScreen(
          initialVersionId: widget.versionId,
          initialBook: targetBook,
          initialChapter: chapter,
          initialVerse: verse,
          saveProgress: false,
        ),
      ),
    );
  }

  bool _isVerseExpanded = true;
  int? _bookCommentariesCount;
  final Set<String> _expandedExcerpts = {};
  
  // Dictionary/Glossary state
  final DictionaryService _dictionaryService = DictionaryService();
  bool _isDictionaryLoading = true;
  Map<String, List<DictionaryEntry>> _dictionaryEntries = {};
  List<String> _keyTerms = [];
  bool _dictionaryInitialized = false;

  void _copyCommentary(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openBookReader(BuildContext context, BookScriptureLink link) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(
          bookId: link.bookId,
          initialPage: link.pageNumber,
          highlightStartLine: link.startLine,
          highlightEndLine: link.endLine,
        ),
      ),
    );
  }

  String? get _resolvedVersionId {
    if (widget.versionId != null && widget.versionId!.trim().isNotEmpty) {
      return widget.versionId!.trim();
    }
    if (widget.versionLabel != null && widget.versionLabel!.trim().isNotEmpty) {
      final label = widget.versionLabel!.trim().toLowerCase();
      if (label.contains('tamil') || label.contains('தமிழ்') || label.contains('taobvsi')) {
        return 'TAOBVSI';
      }
      if (label.contains('malayalam') || label.contains('മലയാളം') || label.contains('mal')) {
        return 'MAL_IRV';
      }
      if (label.contains('telugu') || label.contains('తెలుగు') || label.contains('tel')) {
        return 'TEL_IRV';
      }
      if (label.contains('hindi') || label.contains('हिन्दी') || label.contains('hin')) {
        return 'HIN_IRV';
      }
      if (label.contains('kannada') || label.contains('ಕನ್ನಡ') || label.contains('kan')) {
        return 'KAN_IRV';
      }
      return widget.versionLabel;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadBookCommentariesCount();
    _loadDictionaryEntries();
    BookNameService().ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _loadBookCommentariesCount() {
    widget.bookCommentariesFuture.then((list) {
      if (mounted) {
        setState(() {
          _bookCommentariesCount = list.length;
        });
      }
    }).catchError((_) {});
  }

  Future<void> _loadDictionaryEntries() async {
    if (_dictionaryInitialized) return;
    _dictionaryInitialized = true;
    
    // Extract key terms from verse text
    _keyTerms = _extractKeyTerms(widget.verseText);
    
    if (_keyTerms.isEmpty) {
      if (mounted) {
        setState(() => _isDictionaryLoading = false);
      }
      return;
    }

    setState(() => _isDictionaryLoading = true);
    
    final entriesMap = <String, List<DictionaryEntry>>{};
    
    // Detect language from verse text
    final langCode = DictionaryService.detectLanguageCode(widget.verseText);
    
    for (final term in _keyTerms) {
      try {
        final entries = await _dictionaryService.lookupWord(
          term,
          preferredLangCode: langCode,
        );
        if (entries.isNotEmpty) {
          entriesMap[term] = entries;
        }
      } catch (e) {
        debugPrint('Dictionary lookup error for "$term": $e');
      }
    }

    if (mounted) {
      setState(() {
        _dictionaryEntries = entriesMap;
        _isDictionaryLoading = false;
      });
    }
  }

  List<String> _extractKeyTerms(String verseText) {
    // Clean the verse text and extract meaningful words
    final cleaned = verseText
        .replaceAll(RegExp(r'[০-৯0-9]'), '') // Remove numbers
        .replaceAll(RegExp(r'''[.,;:!?()"'—\-]'''), ' ') // Replace punctuation with space
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
    
    // Split into words and filter
    final words = cleaned.split(' ')
        .map((w) => w.trim())
        .where((w) => w.length >= 3) // Minimum 3 characters
        .where((w) => !RegExp(r'^[\d\s]+$').hasMatch(w)) // Not just numbers
        .where((w) => !_isCommonStopWord(w)) // Filter common stop words
        .toList();
    
    // Take unique words, prioritize Tamil/Sanskrit script words
    final uniqueWords = <String>[];
    final seen = <String>{};
    
    // First pass: Tamil/Sanskrit script words (for Vedagama Agarathi)
    for (final word in words) {
      final lower = word.toLowerCase();
      if (seen.contains(lower)) continue;
      if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(word) || // Tamil
          RegExp(r'[\u0D00-\u0D7F]').hasMatch(word) || // Malayalam
          RegExp(r'[\u0C00-\u0C7F]').hasMatch(word) || // Telugu
          RegExp(r'[\u0C80-\u0CFF]').hasMatch(word) || // Kannada
          RegExp(r'[\u0900-\u097F]').hasMatch(word)) { // Devanagari
        uniqueWords.add(word);
        seen.add(lower);
      }
    }
    
    // Second pass: Other meaningful words
    for (final word in words) {
      if (uniqueWords.length >= 15) break; // Limit to 15 terms
      final lower = word.toLowerCase();
      if (seen.contains(lower)) continue;
      if (word.length >= 4) { // Slightly longer minimum for non-script words
        uniqueWords.add(word);
        seen.add(lower);
      }
    }
    
    return uniqueWords.take(15).toList(); // Max 15 terms
  }

  bool _isCommonStopWord(String word) {
    final stopWords = {
      // English
      'the', 'and', 'for', 'are', 'but', 'not', 'you', 'your', 'with', 'this', 'that', 'have', 'has', 'had', 'was', 'were', 'been', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'from', 'they', 'them', 'their', 'there', 'then', 'than', 'into', 'unto', 'upon', 'over', 'under', 'after', 'before', 'while', 'when', 'where', 'what', 'which', 'who', 'whom', 'whose', 'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such', 'only', 'own', 'same', 'so', 'too', 'very',
      // Tamil common particles
      'அவன்', 'அவள்', 'அவர்கள்', 'நான்', 'நீ', 'நாம்', 'நாங்கள்', 'என்', 'உன்', 'அது', 'இது', 'அவை', 'இவை', 'எந்த', 'எது', 'எப்படி', 'எப்போது', 'எங்கே', 'என்', 'ஆக', 'ஆய்', 'என்றால்', 'ஆனால்', 'ஆலே', 'அதே', 'இதே', 'மட்டும்', 'மேலும்', 'மற்றும்', 'அல்லது', 'ஆகும்', 'இருந்து', 'வரை', 'போல்', 'போலே', 'தான்', 'தானே', 'தான்', 'உம்', 'வ­zie', 'என்று', 'என்றும்', 'அன்றோ', 'இன்றோ',
    };
    return stopWords.contains(word.toLowerCase());
  }

  @override
  void didUpdateWidget(covariant VerseStudyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookCommentariesFuture != widget.bookCommentariesFuture) {
      _loadBookCommentariesCount();
    }
  }

  int get _totalCommentaryCount =>
      (_bookCommentariesCount ?? 0) + widget.commentaryNotes.length;

  Widget _buildVerseCard(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? widget.baseFontSize : widget.baseFontSize + 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: tokens.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.verseLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.versionLabel != null && widget.versionLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.versionLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.verseText,
            maxLines: _isVerseExpanded ? null : 3,
            overflow: _isVerseExpanded ? null : TextOverflow.fade,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: fontSize,
              height: 1.6,
            ),
          ),
          if (widget.verseText.length > 160) ...[
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                onTap: () => setState(() => _isVerseExpanded = !_isVerseExpanded),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isVerseExpanded ? 'Show less' : 'Show more',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isVerseExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: tokens.accent,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReferencesTab(BuildContext context) {
    final tokens = context.tokens;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVerseCard(context),
        const SizedBox(height: 16),
        if (widget.references.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off, size: 48, color: tokens.onSurfaceMuted),
                const SizedBox(height: 12),
                Text(
                  'No cross-references for this verse',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                ),
              ],
            ),
          )
        else ...[
          Text(
            '${widget.references.length} cross-reference${widget.references.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final ref in widget.references)
            CrossReferenceCard(
              reference: ref,
              text: widget.resolvedTexts[ref.textKey],
              fontSize: widget.baseFontSize,
              versionId: _resolvedVersionId,
              onTap: () {
                if (widget.onTapReference != null) {
                  widget.onTapReference!(ref);
                } else {
                  _openPassage(ref.bookNumber, ref.chapter, ref.verse);
                }
              },
            ),
        ],
      ],
    );
  }

  Widget _buildCommentaryTab(BuildContext context) {
    return FutureBuilder<List<BookScriptureLink>>(
      future: widget.bookCommentariesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final tokens = context.tokens;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: tokens.onSurfaceMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading commentaries',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        final bookCommentaries = snapshot.data ?? [];
        final totalCount = bookCommentaries.length + widget.commentaryNotes.length;

        final tokens = context.tokens;

        if (totalCount == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 48, color: tokens.onSurfaceMuted),
                  const SizedBox(height: 12),
                  Text(
                    'No commentary for this verse',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (bookCommentaries.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.auto_stories_rounded, size: 16, color: tokens.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${bookCommentaries.length} Zac Poonen ${bookCommentaries.length == 1 ? 'Exposition' : 'Expositions'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final link in bookCommentaries) _buildBookCommentaryItem(context, link),
              const SizedBox(height: 16),
            ],
            if (widget.commentaryNotes.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.history_edu_rounded, size: 16, color: tokens.onSurfaceMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.commentaryNotes.length} Historical & Cultural Commentary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final note in widget.commentaryNotes) _buildCommentaryItem(context, note),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBookCommentaryItem(BuildContext context, BookScriptureLink link) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final textTheme = theme.textTheme;
    final commentaryFontSize = (widget.baseFontSize * 0.92).clamp(14.0, 22.0);
    final excerptKey = 'book_${link.id}_${link.bookId}_${link.pageNumber}';
    final isLong = link.excerpt.length > 240;
    final isExpanded = !isLong || _expandedExcerpts.contains(excerptKey);
    final displayText = isExpanded
        ? link.excerpt
        : '${link.excerpt.substring(0, 240).trim()}...';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Book info & Page badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.bookTitle,
                        style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 13, color: tokens.onSurfaceMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              link.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _openBookReader(context, link),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 12, color: tokens.accent),
                        const SizedBox(width: 5),
                        Text(
                          'Page ${link.pageNumber}',
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Headline / Chapter topic if present
          if (link.headline.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                link.headline,
                style: TextStyle(
                  color: tokens.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],

          // Excerpt block
          if (link.excerpt.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  border: Border(
                    left: BorderSide(color: tokens.accent, width: 3.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarkdownBody(
                      data: displayText,
                      styleSheet: MarkdownStyleSheet(
                        p: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                          color: tokens.onSurface,
                          fontSize: commentaryFontSize,
                          height: 1.6,
                          letterSpacing: 0.15,
                        ),
                        blockquote: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                          color: tokens.onSurfaceMuted,
                          fontSize: commentaryFontSize,
                          height: 1.55,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    if (isLong) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_expandedExcerpts.contains(excerptKey)) {
                              _expandedExcerpts.remove(excerptKey);
                            } else {
                              _expandedExcerpts.add(excerptKey);
                            }
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? 'Show less' : 'Read more',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 15,
                              color: tokens.accent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Action bar footer
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: () => _copyCommentary(
                    context,
                    '${link.bookTitle} (Page ${link.pageNumber}):\n\n${link.excerpt}',
                    'Commentary excerpt',
                  ),
                  icon: Icon(Icons.content_copy_outlined, size: 14, color: tokens.onSurfaceMuted),
                  label: Text(
                    'Copy',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openPassage(link.bookNumber, link.chapter, link.verse),
                      icon: Icon(Icons.menu_book_outlined, size: 14, color: tokens.accent),
                      label: Text(
                        'View in Bible',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _openBookReader(context, link),
                      icon: Icon(Icons.auto_stories_rounded, size: 14, color: tokens.accent),
                      label: Text(
                        'Read in Book',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentaryItem(BuildContext context, BibleBackgroundNote note) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final textTheme = theme.textTheme;
    final commentaryFontSize = (widget.baseFontSize * 0.92).clamp(14.0, 22.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic header & pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    note.topic,
                    style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_edu_rounded, size: 12, color: tokens.accent),
                      const SizedBox(width: 4),
                      Text(
                        note.isChapterOverview ? 'Overview' : 'Context',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Quote container if present
            if (note.quote != null && note.quote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  '“${note.quote}”',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: (commentaryFontSize * 0.88).clamp(12.0, 16.0),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            // Note body
            const SizedBox(height: 12),
            MarkdownBody(
              data: note.text,
              styleSheet: MarkdownStyleSheet(
                p: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                  color: tokens.onSurface,
                  fontSize: commentaryFontSize,
                  height: 1.6,
                  letterSpacing: 0.15,
                ),
              ),
            ),

            // Footer: Verified source attribution & action buttons
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 13, color: tokens.onSurfaceMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    note.source,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _openPassage(
                    note.bookNumber,
                    note.chapter,
                    note.verse > 0 ? note.verse : 1,
                  ),
                  icon: Icon(Icons.menu_book_outlined, size: 13, color: tokens.accent),
                  label: Text(
                    "View in Bible",
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _copyCommentary(
                    context,
                    "${note.topic}:\n${note.text}\n(${note.source})",
                    "Note",
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.content_copy_outlined, size: 12, color: tokens.onSurfaceMuted),
                        const SizedBox(width: 4),
                        Text(
                          "Copy",
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final safeInitialTab = (widget.initialTab >= 0 && widget.initialTab < 3) ? widget.initialTab : 0;

    return DefaultTabController(
      length: 3,
      initialIndex: safeInitialTab,
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.background,
          elevation: 0,
          title: Text(
            'Study (${widget.verseLabel})',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: tokens.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildLayout(context),
      ),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final tokens = context.tokens;
    final dictionaryCount = _dictionaryEntries.length;

    return MaxWidthBox(
      child: Column(
        children: [
          // Tab bar
          Container(
            color: tokens.background,
            child: TabBar(
              indicatorColor: tokens.accent,
              labelColor: tokens.accent,
              unselectedLabelColor: tokens.onSurfaceMuted,
              tabs: [
                Tab(
                  icon: const Icon(Icons.link, size: 18),
                  text: 'References (${widget.references.length})',
                ),
                Tab(
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  text: 'Commentary ($_totalCommentaryCount)',
                ),
                Tab(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  text: 'Glossary ($dictionaryCount)',
                ),
              ],
            ),
          ),

          // Scrollable content per tab
          Expanded(
            child: TabBarView(
              children: [
                _buildReferencesTab(context),
                _buildCommentaryTab(context),
                _buildDictionaryTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryTab(BuildContext context) {
    final tokens = context.tokens;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVerseCard(context),
        const SizedBox(height: 16),
        if (_isDictionaryLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: tokens.accent),
                  const SizedBox(height: 12),
                  Text(
                    'Loading dictionary definitions...',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else if (_dictionaryEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_outlined, size: 48, color: tokens.onSurfaceMuted),
                const SizedBox(height: 12),
                Text(
                  'No glossary terms found for this verse',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (_keyTerms.isNotEmpty) ...[
                  Text(
                    'Terms searched: ${_keyTerms.join(', ')}',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/downloads');
                  },
                  icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                  label: const Text('Download Tamil Vedagama Agarathi'),
                ),
              ],
            ),
          )
        else ...[
          Text(
            '${_dictionaryEntries.length} term${_dictionaryEntries.length == 1 ? '' : 's'} found in Vedagama Agarathi',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in _dictionaryEntries.entries)
            _buildDictionaryEntryCard(context, entry.key, entry.value),
        ],
      ],
    );
  }

  Widget _buildDictionaryEntryCard(BuildContext context, String term, List<DictionaryEntry> entries) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Term header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border(
                bottom: BorderSide(color: tokens.surfaceBorder),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    term,
                    style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'serif',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${entries.length} definition${entries.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Definitions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _buildDictionaryDefinitionItem(entries[i], tokens),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryDefinitionItem(DictionaryEntry entry, AppTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (entry.partOfSpeech.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Text(
                  entry.partOfSpeech.toLowerCase(),
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              entry.source,
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.definition,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
        if (entry.examples.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '“${entry.examples}”',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
