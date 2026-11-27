import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile/shared/ui/reader_selection_line.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/link/deep_link_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/core/services/reader_fullscreen_service.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/reader_selection_toolbar.dart';
import 'package:mobile/features/books/widgets/scripture_verse_popup.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';
import 'package:mobile/shared/ui/double_tap_dictionary_area.dart';
import 'package:mobile/shared/ui/widgets/reader_appearance_action_button.dart';
import 'package:mobile/shared/ui/reader_fullscreen_button.dart';
import 'package:mobile/shared/ui/reader_appearance_sheet.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/article_reader_controller.dart';
import '../models/wftw_index_entry.dart';
import '../services/article_sync_service.dart';

class ArticleReaderScreen extends StatefulWidget {
  final String articleId;
  final String lang;
  final String? initialTitle;
  final ArticleSyncService? syncService;

  const ArticleReaderScreen({
    super.key,
    required this.articleId,
    this.lang = 'en',
    this.initialTitle,
    this.syncService,
  });

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  static const String _readerId = 'article';
  final ReaderFullscreenService _fullscreen = ReaderFullscreenService.instance;
  late final ArticleReaderController _controller;
  final ScrollController _scrollController = ScrollController();
  final List<GestureRecognizer> _recognizers = [];
  final Map<int, SelectedContentRange> _selectedRanges = {};
  List<BookHighlight> _articleHighlights = const [];
  String get _articleScope => 'article_${widget.articleId}_${widget.lang}';

  @override
  void initState() {
    super.initState();
    _fullscreen.attach(_readerId);
    _controller = ArticleReaderController(
      widget.articleId,
      lang: widget.lang,
      syncService: widget.syncService,
    );
    _loadArticleHighlights();
    _controller.appearance.addListener(_onAppearanceChanged);
    ReaderFontsService.instance.addListener(_onFontsChanged);

    // Load localized book names so scripture references in the article's
    // language resolve to tappable verse popups.
    BookNameService().ensureLoaded().then((_) {
      ScriptureRefParser.refreshRuntimeBookNumbers();
    });
  }

  @override
  void dispose() {
    _fullscreen.detach(_readerId);
    _controller.appearance.removeListener(_onAppearanceChanged);
    ReaderFontsService.instance.removeListener(_onFontsChanged);
    _disposeRecognizers();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onAppearanceChanged() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final ratio = maxExtent > 0 ? _scrollController.offset / maxExtent : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final newMax = _scrollController.position.maxScrollExtent;
      if (newMax > 0) {
        _scrollController.jumpTo((ratio * newMax).clamp(0.0, newMax));
      }
    });
  }

  void _onFontsChanged() {
    if (mounted) setState(() {});
  }

  void _shareArticle() {
    final article = _controller.state.article;
    if (article == null) return;
    final link = DeepLinkService.article(widget.articleId, lang: widget.lang);
    final buffer = StringBuffer()
      ..writeln(article.title)
      ..writeln('By ${article.author} • ${article.date}\n');
    for (final line in article.lines.take(12)) {
      buffer.writeln(line.text);
    }
    buffer.writeln('${AppLocalizations.maybeOf(context)?.readOnApp ?? 'Read on App'}: $link');
    Share.share(buffer.toString(), subject: article.title);
  }

  Future<void> _loadArticleHighlights() async {
    try {
      final highlights = await BookService.instance.getHighlightsForBook(_articleScope);
      if (mounted) setState(() => _articleHighlights = highlights);
    } catch (_) {
      // The reader remains usable if annotation storage is unavailable.
    }
  }

  Future<void> _saveArticleHighlight(String text, int colorIndex) async {
    final article = _controller.state.article;
    if (article == null) return;
    final ranges = Map<int, SelectedContentRange>.of(_selectedRanges);
    var saved = 0;
    for (final entry in ranges.entries) {
      if (entry.key < 0 || entry.key >= article.lines.length) continue;
      final line = article.lines[entry.key].text;
      final start = entry.value.startOffset.clamp(0, line.length);
      final end = entry.value.endOffset.clamp(start, line.length);
      if (start == end) continue;
      final highlight = BookHighlight(
        id: 'article_range_${widget.articleId}_${widget.lang}_${entry.key}_${DateTime.now().microsecondsSinceEpoch}',
        bookId: _articleScope,
        chapterIndex: 1,
        pageNumber: entry.key + 1,
        startChar: start,
        endChar: end,
        text: line.substring(start, end),
        color: colorIndex,
        createdAt: DateTime.now().toIso8601String(),
      );
      await BookService.instance.saveHighlight(highlight);
      saved++;
    }
    if (saved == 0) return;
    await _loadArticleHighlights();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Highlight saved'), duration: Duration(seconds: 1),
      ));
    }
  }

  Future<void> _clearArticleHighlights(String text, int page) async {
    final ranges = Map<int, SelectedContentRange>.of(_selectedRanges);
    for (final h in _articleHighlights) {
      if (!h.id.startsWith('article_range_')) continue;
      final range = ranges[h.pageNumber - 1];
      if (range != null && h.startChar < range.endOffset && h.endChar > range.startOffset) {
        await BookService.instance.deleteHighlight(h.id);
      }
    }
    await _loadArticleHighlights();
  }

  /// Disposes every recognizer created so far. Called before each build pass
  /// (spans are rebuilt wholesale) and on dispose, so recognizers do not
  /// accumulate while a reader stays on screen and rebuilds.
  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _makeRecognizer(ParsedScriptureRef? parsed, String refText) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        if (parsed != null && mounted) {
          ScriptureVersePopup.show(
            context,
            bookNumber: parsed.bookNumber,
            chapter: parsed.chapter,
            startVerse: parsed.startVerse,
            endVerse: parsed.endVerse,
            rawReference: refText,
            languageCode: widget.lang,
          );
        }
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  List<InlineSpan> _buildSpans(
    String text,
    Color textColor,
    String? fontFamily,
    ReaderAppearance appearance,
    AppTokens tokens,
    int lineIndex, {
    bool isHeading = false,
  }) {
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: isHeading ? appearance.fontSize * 1.25 : appearance.fontSize,
      height: isHeading ? 1.3 : appearance.lineHeight,
      fontFamily: fontFamily,
      fontWeight: isHeading ? FontWeight.bold : appearance.fontWeight,
      fontStyle: appearance.fontStyle,
      decoration: appearance.textDecoration,
    );

    final textTokens = ScriptureRefParser.tokenize(text);
    final spans = <InlineSpan>[];

    var offset = 0;
    final highlights = _articleHighlights.where((h) =>
        h.id.startsWith('article_range_') && h.pageNumber == lineIndex + 1);
    for (final token in textTokens) {
      final tokenStart = offset;
      final tokenEnd = tokenStart + token.text.length;
      final boundaries = <int>{tokenStart, tokenEnd};
      for (final h in highlights) {
        if (h.startChar < tokenEnd && h.endChar > tokenStart) {
          boundaries.add(h.startChar.clamp(tokenStart, tokenEnd));
          boundaries.add(h.endChar.clamp(tokenStart, tokenEnd));
        }
      }
      final cuts = boundaries.toList()..sort();
      for (var i = 0; i + 1 < cuts.length; i++) {
        final start = cuts[i], end = cuts[i + 1];
        BookHighlight? highlight;
        for (final h in highlights) {
          if (h.startChar <= start && h.endChar >= end) highlight = h;
        }
        final isReference = token.isReference && token.ref != null;
        var style = isReference
            ? baseStyle.copyWith(
                color: tokens.accent, fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: tokens.accent.withValues(alpha: 0.6))
            : baseStyle;
        if (highlight != null) {
          style = style.copyWith(backgroundColor:
              ReaderAppearance.highlightColorByIndex(highlight.color).withValues(alpha: 0.38));
        }
        spans.add(TextSpan(
          text: token.text.substring(start - tokenStart, end - tokenStart),
          style: style,
          recognizer: isReference ? _makeRecognizer(token.ref, token.text) : null,
        ));
      }
      offset = tokenEnd;
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _controller.appearance, _fullscreen]),
      builder: (context, _) {
        _disposeRecognizers();
        final l10n = AppLocalizations.maybeOf(context);
        final state = _controller.state;
        final appearance = _controller.appearance;
        final fontFamily = ScriptureThemeCatalog.resolveFontFamily(
          appearance.fontFamily,
          appearance.languageCode,
        );

        final title = state.article?.title ?? widget.initialTitle ?? l10n?.appTitle ?? 'Article';

        final isFullscreen = _fullscreen.isFullscreenFor(_readerId);
        return PopScope(
          canPop: !isFullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _fullscreen.isFullscreenFor(_readerId)) {
              _fullscreen.exit(_readerId);
            }
          },
          child: Listener(
            onPointerDown: (_) => _fullscreen.noteActivity(_readerId),
            child: Scaffold(
          backgroundColor: appearance.background(tokens),
          appBar: isFullscreen ? null : AppBar(
            backgroundColor: appearance.surface(tokens),
            elevation: 0,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appearance.textColor(tokens),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            automaticallyImplyLeading: false,
            actions: needsCollapsedActions(MediaQuery.sizeOf(context).width)
                ? [
                    PopupMenuButton<String>(
                      tooltip: 'Reader options',
                      color: appearance.surface(tokens),
                      onSelected: (value) {
                        if (value == 'appearance') {
                          showReaderAppearanceSheet(context, appearance);
                        } else if (value == 'fullscreen') {
                          _fullscreen.toggle(_readerId);
                        } else if (value == 'share') {
                          _shareArticle();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'appearance', child: Text('Reading appearance')),
                        const PopupMenuItem(value: 'fullscreen', child: Text('Fullscreen reading')),
                        if (state.article != null)
                          const PopupMenuItem(value: 'share', child: Text('Share article')),
                      ],
                    ),
                  ]
                : [
              // Standardized Aa typography appearance button
              ReaderAppearanceActionButton(appearance: appearance),
              IconButton(
                tooltip: 'Enter fullscreen reading',
                icon: Icon(Icons.fullscreen_rounded,
                    color: appearance.textColor(tokens)),
                onPressed: () => _fullscreen.toggle(_readerId),
              ),

              // Share button
              if (state.article != null)
                IconButton(
                  icon: Icon(Icons.share_rounded, color: appearance.textColor(tokens)),
                  tooltip: l10n?.share ?? 'Share',
                  onPressed: _shareArticle,
                ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _buildBody(state, tokens, fontFamily, appearance, l10n),
              if (isFullscreen)
                ReaderFullscreenButton(
                  onExit: () => _fullscreen.exit(_readerId),
                ),
            ],
          ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    ArticleReaderState state,
    AppTokens tokens,
    String? fontFamily,
    ReaderAppearance appearance,
    AppLocalizations? l10n,
  ) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: tokens.accent,
          strokeWidth: 2.5,
        ),
      );
    }

    if (state.hasError && state.article == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.signal_wifi_connected_no_internet_4_rounded,
                color: tokens.onSurfaceMuted,
                size: 54,
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.articleReadError ?? 'Unable to load article',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _controller.loadArticle,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n?.retry ?? 'Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.background,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final article = state.article!;
    final textColor = appearance.textColor(tokens);
    final mutedColor = appearance.mutedTextColor(tokens);

    return Center(
      child: MaxWidthBox(
        maxWidth: kReadingMaxWidth,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          style: TextStyle(
            color: textColor,
            fontFamily: fontFamily,
            fontSize: appearance.fontSize,
            height: appearance.lineHeight,
            fontWeight: appearance.fontWeight,
            fontStyle: appearance.fontStyle,
          ),
          child: DoubleTapDictionaryArea(
            contextMenuBuilder: (context, selectableRegionState, selectedText) {
              return buildReaderSelectionToolbar(
                context,
                selectableRegionState,
                1,
                selectedText: selectedText,
                onClearHighlight: _clearArticleHighlights,
                onHighlight: (text, _) => _saveArticleHighlight(text, 0),
                onHighlightWithColor: (text, _, colorIndex) =>
                    _saveArticleHighlight(text, colorIndex),
              );
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Metadata: Author & Date
                    Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 16, color: mutedColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            article.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today_rounded, size: 14, color: mutedColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            formatWftwDate(article.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: appearance.surfaceBorder(tokens), height: 1),
                    const SizedBox(height: 20),

                    // Paragraphs & Headings
                    ...article.lines.asMap().entries.map((entry) {
                      final line = entry.value;
                      final lineIndex = entry.key;
                      return ReaderSelectionLine(
                        key: ValueKey('article-line-$lineIndex'),
                        onSelection: (range) {
                          if (range == null || range.startOffset == range.endOffset) {
                            _selectedRanges.remove(lineIndex);
                          } else {
                            _selectedRanges[lineIndex] = range;
                          }
                        },
                        child: Padding(
                          padding: line.isHeading
                              ? const EdgeInsets.only(top: 24, bottom: 12)
                              : const EdgeInsets.only(bottom: 16),
                          child: Text.rich(
                            TextSpan(children: _buildSpans(line.text, textColor,
                                fontFamily, appearance, tokens, lineIndex, isHeading: line.isHeading)),
                            style: line.isHeading ? TextStyle(
                              color: textColor, fontSize: appearance.fontSize * 1.25,
                              fontWeight: FontWeight.bold, height: 1.3, fontFamily: fontFamily,
                            ) : null,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 64),
                  ]),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
