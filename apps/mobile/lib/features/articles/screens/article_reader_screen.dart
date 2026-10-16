import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/link/deep_link_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/scripture_verse_popup.dart';
import 'package:mobile/features/dictionary/widgets/glossary_entry_sheet.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';
import 'package:mobile/shared/ui/widgets/reader_appearance_action_button.dart';
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
  late final ArticleReaderController _controller;
  final ScrollController _scrollController = ScrollController();
  final List<GestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _controller = ArticleReaderController(
      widget.articleId,
      lang: widget.lang,
      syncService: widget.syncService,
    );
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
  ) {
    final matches = ScriptureRefParser.scriptureRegex.allMatches(text).toList();
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: appearance.fontSize,
      height: appearance.lineHeight,
      fontFamily: fontFamily,
      fontWeight: appearance.fontWeight,
      fontStyle: appearance.fontStyle,
      decoration: appearance.textDecoration,
    );

    if (matches.isEmpty) {
      final spans = <InlineSpan>[];
      _addWordSpans(spans, text, baseStyle);
      return spans;
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        _addWordSpans(spans, text.substring(lastMatchEnd, match.start), baseStyle);
      }

      final refText = match.group(0)!;
      final parsed = ScriptureRefParser.parse(refText);

      spans.add(TextSpan(
        text: refText,
        style: baseStyle.copyWith(
          color: tokens.accent,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationColor: tokens.accent.withValues(alpha: 0.6),
        ),
        recognizer: _makeRecognizer(parsed, refText),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      _addWordSpans(spans, text.substring(lastMatchEnd), baseStyle);
    }

    return spans;
  }

  void _addWordSpans(List<InlineSpan> spans, String chunk, TextStyle style) {
    final tokens = chunk.split(RegExp(r'(\s+)'));
    for (final token in tokens) {
      if (token.isEmpty) continue;
      if (RegExp(r'^\s+$').hasMatch(token)) {
        spans.add(TextSpan(text: token, style: style));
        continue;
      }
      final clean = token.replaceAll(
        RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''),
        '',
      );
      if (clean.isEmpty) {
        spans.add(TextSpan(text: token, style: style));
        continue;
      }

      final recognizer = LongPressGestureRecognizer()
        ..onLongPress = () {
          if (mounted) {
            GlossaryEntrySheet.show(context, word: clean);
          }
        };
      _recognizers.add(recognizer);

      spans.add(TextSpan(
        text: token,
        style: style,
        recognizer: recognizer,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _controller.appearance]),
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

        return Scaffold(
          backgroundColor: appearance.background(tokens),
          appBar: AppBar(
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
            actions: [
              // Standardized Aa typography appearance button
              ReaderAppearanceActionButton(appearance: appearance),

              // Share button
              if (state.article != null)
                IconButton(
                  icon: Icon(Icons.share_rounded, color: appearance.textColor(tokens)),
                  tooltip: l10n?.share ?? 'Share',
                  onPressed: () {
                    final article = state.article!;
                    final link = DeepLinkService.article(
                      widget.articleId,
                      lang: widget.lang,
                    );
                    final buffer = StringBuffer();
                    buffer.writeln(article.title);
                    buffer.writeln('By ${article.author} • ${article.date}\n');
                    for (final l in article.lines.take(12)) {
                      buffer.writeln(l.text);
                    }
                    buffer.writeln('${l10n?.readOnApp ?? 'Read on App'}: $link');
                    Share.share(
                      buffer.toString(),
                      subject: article.title,
                    );
                  },
                ),
            ],
          ),
          body: _buildBody(state, tokens, fontFamily, appearance, l10n),
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
                    ...article.lines.map((line) {
                      if (line.isHeading) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 12),
                          child: Text(
                            line.text,
                            style: TextStyle(
                              color: textColor,
                              fontSize: appearance.fontSize * 1.25,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                              fontFamily: fontFamily,
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: RichText(
                          text: TextSpan(
                            children: _buildSpans(
                              line.text,
                              textColor,
                              fontFamily,
                              appearance,
                              tokens,
                            ),
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
    );
  }
}
