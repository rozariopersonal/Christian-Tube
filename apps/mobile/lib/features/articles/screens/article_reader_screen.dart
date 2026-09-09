import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/link/deep_link_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/scripture_verse_popup.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/ui/reader_appearance_sheet.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/article_reader_controller.dart';
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
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _controller = ArticleReaderController(
      widget.articleId,
      lang: widget.lang,
      syncService: widget.syncService,
    );
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    _controller.dispose();
    super.dispose();
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
    double fontSize,
    double lineHeight,
    AppTokens tokens,
  ) {
    final matches = ScriptureRefParser.scriptureRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return [
        TextSpan(
          text: text,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            height: lineHeight,
            fontFamily: fontFamily,
          ),
        ),
      ];
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            height: lineHeight,
            fontFamily: fontFamily,
          ),
        ));
      }

      final refText = match.group(0)!;
      final parsed = ScriptureRefParser.parse(refText);

      spans.add(TextSpan(
        text: refText,
        style: TextStyle(
          color: tokens.accent,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationColor: tokens.accent.withValues(alpha: 0.6),
          fontSize: fontSize,
          height: lineHeight,
          fontFamily: fontFamily,
        ),
        recognizer: _makeRecognizer(parsed, refText),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          height: lineHeight,
          fontFamily: fontFamily,
        ),
      ));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final appearance = _controller.appearance;
        final fontFamily = ScriptureThemeCatalog.resolveFontFamily(
          appearance.fontFamily,
          appearance.languageCode,
        );

        final title = state.article?.title ?? widget.initialTitle ?? 'Article';

        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.surface,
            elevation: 0,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: tokens.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              // Aa typography appearance button
              IconButton(
                icon: Text(
                  'Aa',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                tooltip: 'Appearance',
                onPressed: () => showReaderAppearanceSheet(context, appearance),
              ),

              // Share button
              if (state.article != null)
                IconButton(
                  icon: Icon(Icons.share_rounded, color: tokens.onSurface),
                  tooltip: 'Share',
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
                    buffer.writeln('\nRead on ChristianApp: $link');
                    Share.share(
                      buffer.toString(),
                      subject: article.title,
                    );
                  },
                ),
            ],
          ),
          body: _buildBody(state, tokens, fontFamily, appearance),
        );
      },
    );
  }

  Widget _buildBody(
    ArticleReaderState state,
    AppTokens tokens,
    String? fontFamily,
    dynamic appearance,
  ) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: tokens.accent,
          strokeWidth: 2.5,
        ),
      );
    }

    if (state.errorMessage != null && state.article == null) {
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
                state.errorMessage!,
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
                label: const Text('Retry'),
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
    final textColor = tokens.onSurface;
    final mutedColor = tokens.onSurfaceMuted;

    return Center(
      child: MaxWidthBox(
        maxWidth: 740,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Article Title
                  Text(
                    article.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: appearance.fontSize * 1.5,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                      fontFamily: fontFamily,
                    ),
                  ),
                  const SizedBox(height: 12),

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
                          article.date,
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
                  Divider(color: tokens.surfaceBorder, height: 1),
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
                            appearance.fontSize,
                            appearance.lineHeight,
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
    );
  }
}
