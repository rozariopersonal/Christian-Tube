import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';
import '../../../features/engines/scripture/models/scripture_theme_state.dart';
import '../models/bible_verse.dart';
import '../../../shared/services/reader_appearance.dart';

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

  @override
  void dispose() {
    _hoverNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appearance,
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
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          child: MouseRegion(
            onEnter: (_) => _hoverNotifier.value = true,
            onExit: (_) => _hoverNotifier.value = false,
            cursor: SystemMouseCursors.click,
            child: ValueListenableBuilder<bool>(
              valueListenable: _hoverNotifier,
              builder: (context, isHovering, _) {
                // A persistent highlight keeps its own marker colour. When such
                // a verse is also selected we show selection via an underline
                // instead of swapping the marker for the selection tint.
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

                final hasHighlight = highlightFill != null;
                final showUnderline = widget.isSelected && hasPersistentHighlight;

                final Widget verseBody;
                if (isHovering && !hasHighlight) {
                  verseBody = Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      color: widget
                          .appearance
                          .textColor(context.tokens)
                          .withValues(alpha: 0.06),
                      child: _buildContent(context, theme, highlightColor),
                    ),
                  );
                } else {
                  // Marker-pen highlight: the background is applied directly to
                  // the text style so each rendered line gets its own marker
                  // bar that hugs the line width (natural ragged edge on
                  // wrapped lines) and fills the line-height gaps. The box
                  // approach is intentionally avoided -- it paints one rectangle
                  // around the whole paragraph instead of per-line marks. This
                  // also never changes the text layout.
                  verseBody = _buildContent(context, theme, highlightColor,
                      highlightOn: hasHighlight ? highlightFill : null,
                      underline: showUnderline);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
                  child: verseBody,
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
    Color? highlightColor, {
    Color? highlightOn,
    bool underline = false,
  }) {
    final tokens = context.tokens;
    final app = widget.appearance;
    final fontFamily = ScriptureThemeCatalog.resolveFontFamily(app.fontFamily, app.languageCode);

    // When a highlight is applied the entire text block flips to the contrast
    // color so dark highlights get white text and light highlights stay dark.
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

    return Text.rich(
      TextSpan(
        style: highlightOn != null ? TextStyle(backgroundColor: highlightOn) : null,
        children: [
          TextSpan(
            text: '${widget.verse.number}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor,
              fontWeight: FontWeight.bold,
              fontSize: app.fontSize * 0.7,
              fontFamily: fontFamily,
              decoration: underline ? TextDecoration.underline : null,
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
          TextSpan(
            text: ' ${widget.verse.text}',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: app.lineHeight,
              fontSize: app.fontSize,
              fontFamily: fontFamily,
              color: bodyTextColor,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ],
      ),
    );
  }
}