import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';
import '../../../features/engines/scripture/models/scripture_theme_state.dart';
import '../../dictionary/widgets/glossary_entry_sheet.dart';
import '../models/bible_verse.dart';
import '../../../shared/services/reader_appearance.dart';
import '../../../shared/services/reader_fonts_service.dart';
import 'verse_highlight_layer.dart';

class VerseText extends StatefulWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final int? highlightColorIndex;
  final VoidCallback? onTap;
  final ReaderAppearance appearance;
  final int refCount;
  final int commentaryCount;
  final bool hasNote;

  const VerseText({
    super.key,
    required this.verse,
    this.isSelected = false,
    this.isHighlighted = false,
    this.highlightColorIndex,
    this.onTap,
    required this.appearance,
    this.refCount = 0,
    this.commentaryCount = 0,
    this.hasNote = false,
  });

  @override
  State<VerseText> createState() => _VerseTextState();
}

class _VerseTextState extends State<VerseText> {
  late final ValueNotifier<bool> _hoverNotifier = ValueNotifier<bool>(false);
  final List<GestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _hoverNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.appearance, ReaderFontsService.instance]),
      builder: (context, _) {
        final theme = Theme.of(context);
        if (widget.verse.isChapterHeader) {
          return Padding(
            padding: const EdgeInsets.only(top: 32.0, bottom: 16.0, left: 16.0, right: 16.0),
            child: Text(
              widget.verse.chapterTitle ?? '',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        final highlightColor =
            widget.highlightColorIndex == null
                ? null
                : HighlightPalette.colorFor(widget.highlightColorIndex!);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: MouseRegion(
            onEnter: (_) => _hoverNotifier.value = true,
            onExit: (_) => _hoverNotifier.value = false,
            cursor: SystemMouseCursors.click,
            child: ValueListenableBuilder<bool>(
              valueListenable: _hoverNotifier,
              builder: (context, isHovering, _) {
                final bool hasPersistentHighlight = highlightColor != null;
                final Color? highlightFill;
                if (hasPersistentHighlight) {
                  highlightFill = highlightColor;
                } else if (widget.isSelected) {
                  highlightFill = theme.colorScheme.primary.withValues(alpha: 0.22);
                } else if (widget.isHighlighted) {
                  highlightFill = widget.appearance.isDark(context.tokens)
                      ? theme.colorScheme.primary.withValues(alpha: 0.28)
                      : theme.colorScheme.primaryContainer;
                } else {
                  highlightFill = null;
                }

                final hoverFill = widget.appearance
                    .textColor(context.tokens)
                    .withValues(alpha: 0.06);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
                  child: VerseHighlightLayer(
                    highlightColor: highlightFill,
                    isHovered: isHovering,
                    hoverColor: hoverFill,
                    child: _buildContent(context, theme, highlightColor),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    Color? highlightColor,
  ) {
    final tokens = context.tokens;
    final app = widget.appearance;
    final fontFamily = ScriptureThemeCatalog.resolveFontFamily(app.fontFamily, app.languageCode);

    // Contrast foreground color for persistent highlights
    final hasHighlight = highlightColor != null;
    final mutedTextColor = hasHighlight
        ? HighlightPalette.onColorFor(widget.highlightColorIndex!).withValues(alpha: 0.75)
        : app.mutedTextColor(tokens);
    final bodyTextColor = hasHighlight
        ? HighlightPalette.onColorFor(widget.highlightColorIndex!)
        : widget.verse.isSecondary
            ? app.mutedTextColor(tokens)
            : app.textColor(tokens);
    final iconColor = hasHighlight
        ? HighlightPalette.onColorFor(widget.highlightColorIndex!).withValues(alpha: 0.85)
        : theme.colorScheme.primary.withValues(alpha: 0.7);

    _disposeRecognizers();
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      height: app.lineHeight,
      fontSize: app.fontSize,
      fontFamily: fontFamily,
      color: bodyTextColor,
      fontWeight: app.fontWeight,
      fontStyle: app.fontStyle,
      decoration: app.textDecoration,
    );

    return Text.rich(
      TextSpan(
        children: [
          if (hasHighlight)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.0),
                margin: const EdgeInsets.only(right: 2.5),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    const Color(0xFF000000).withValues(alpha: 0.28),
                    highlightColor,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.verse.verseDisplay,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: HighlightPalette.onColorFor(widget.highlightColorIndex!),
                    fontWeight: FontWeight.bold,
                    fontSize: app.fontSize * 0.65,
                    fontFamily: fontFamily,
                    height: 1.1,
                  ),
                ),
              ),
            )
          else
            TextSpan(
              text: widget.verse.verseDisplay,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor,
                fontWeight: FontWeight.bold,
                fontSize: app.fontSize * 0.7,
                fontFamily: fontFamily,
              ),
            ),
          if (widget.refCount > 0)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 2.0, right: 1.0, top: 2.0),
                child: Icon(
                  Icons.link_rounded,
                  size: app.fontSize * 0.45,
                  color: iconColor,
                ),
              ),
            ),
          if (widget.commentaryCount > 0)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 1.0, right: 1.0, top: 2.0),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: app.fontSize * 0.45,
                  color: iconColor,
                ),
              ),
            ),
          if (widget.hasNote)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 1.0, right: 1.0, top: 2.0),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: app.fontSize * 0.45,
                  color: iconColor,
                ),
              ),
            ),
          const TextSpan(text: ' '),
          ..._buildWordSpans(widget.verse.text, bodyStyle ?? const TextStyle()),
        ],
      ),
      strutStyle: StrutStyle(
        fontFamily: fontFamily,
        fontSize: app.fontSize,
        height: app.lineHeight,
        forceStrutHeight: false,
      ),
    );
  }

  List<InlineSpan> _buildWordSpans(String verseText, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final tokens = verseText.split(RegExp(r'(\s+)'));
    for (final token in tokens) {
      if (token.isEmpty) continue;
      if (RegExp(r'^\s+$').hasMatch(token)) {
        spans.add(TextSpan(text: token, style: baseStyle));
        continue;
      }
      final clean = token.replaceAll(
        RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''),
        '',
      );
      if (clean.isEmpty) {
        spans.add(TextSpan(text: token, style: baseStyle));
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
        style: baseStyle,
        recognizer: recognizer,
      ));
    }
    return spans;
  }
}