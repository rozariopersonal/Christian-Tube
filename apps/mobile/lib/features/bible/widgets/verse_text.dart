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

  /// When a highlight is active, these control whether the highlight
  /// marker extends into the vertical gap toward the neighbouring verse to
  /// render a continuous highlight across consecutive verses.
  /// A value of `0` means the neighbour shares the same highlight colour and
  /// the marker should fill the gap; any other value keeps a normal gap.
  final double? highlightStartPadding;
  final double? highlightEndPadding;

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
    this.highlightStartPadding,
    this.highlightEndPadding,
  });

  @override
  State<VerseText> createState() => _VerseTextState();
}

class _VerseTextState extends State<VerseText> {
  // Total vertical gap between two adjacent verse rows (each contributes
  // 6.0 of outer top/bottom padding) that must be spanned by the highlight
  // marker so consecutive highlighted verses render without a break.
  static const double _kInterVerseGap = 12.0;

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
                final Color? highlightFill;
                if (widget.isSelected) {
                  highlightFill = theme.colorScheme.primary.withValues(alpha: 0.22);
                } else if (highlightColor != null) {
                  highlightFill = highlightColor;
                } else if (widget.isHighlighted) {
                  highlightFill = widget.appearance.isDark(context.tokens)
                      ? theme.colorScheme.primary.withValues(alpha: 0.28)
                      : theme.colorScheme.primaryContainer;
                } else {
                  highlightFill = null;
                }

                final hasHighlightBg = highlightFill != null;

                // The highlight only reaches the text length (marker-pen
                // look) and does not change the text layout. We anchor on
                // the text's intrinsic width rather than filling the row.
                final content = _buildContent(context, theme, highlightColor);

                final Widget verseBody;
                if (hasHighlightBg) {
                  // When a neighbouring verse shares this highlight colour,
                  // extend the marker into the inter-verse gap (and square the
                  // corner on that side) so consecutive verses form one clean
                  // continuous highlight band.
                  final topJoined = (widget.highlightStartPadding ?? 6.0) == 0.0;
                  final bottomJoined = (widget.highlightEndPadding ?? 6.0) == 0.0;
                  final topExtend = topJoined ? _kInterVerseGap : 0.0;
                  final bottomExtend = bottomJoined ? _kInterVerseGap : 0.0;
                  final radius = 4.0;
                  verseBody = Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: highlightFill,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(topJoined ? 0.0 : radius),
                          bottom: Radius.circular(bottomJoined ? 0.0 : radius),
                        ),
                      ),
                      padding: EdgeInsets.only(
                        left: 3.0,
                        right: 3.0,
                        top: 1.0 + topExtend,
                        bottom: 1.0 + bottomExtend,
                      ),
                      child: content,
                    ),
                  );
                } else if (isHovering) {
                  verseBody = Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      color: widget
                          .appearance
                          .textColor(context.tokens)
                          .withValues(alpha: 0.06),
                      child: content,
                    ),
                  );
                } else {
                  verseBody = content;
                }

                // Constant outer vertical padding so highlighting never
                // shifts the surrounding text layout.
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
    Color? highlightColor,
  ) {
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
        children: [
          TextSpan(
            text: '${widget.verse.number}',
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
          TextSpan(
            text: ' ${widget.verse.text}',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: app.lineHeight,
              fontSize: app.fontSize,
              fontFamily: fontFamily,
              color: bodyTextColor,
            ),
          ),
        ],
      ),
    );
  }
}