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
  });

  @override
  State<VerseText> createState() => _VerseTextState();
}

class _VerseTextState extends State<VerseText> {
  Offset? _downPosition;
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

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => _downPosition = event.position,
          onPointerUp: (event) {
            if (_downPosition != null && (event.position - _downPosition!).distance < 18) {
              widget.onTap?.call();
            }
          },
          child: MouseRegion(
            onEnter: (_) => _hoverNotifier.value = true,
            onExit: (_) => _hoverNotifier.value = false,
            cursor: SystemMouseCursors.click,
            child: ValueListenableBuilder<bool>(
              valueListenable: _hoverNotifier,
              builder: (context, isHovering, _) {
                final Color? background;
                if (widget.isSelected) {
                  background = theme.colorScheme.primary.withValues(alpha: 0.22);
                } else if (highlightColor != null) {
                  background = highlightColor;
                } else if (widget.isHighlighted) {
                  background = widget.appearance.isDark(context.tokens)
                      ? theme.colorScheme.primary.withValues(alpha: 0.28)
                      : theme.colorScheme.primaryContainer;
                } else if (isHovering) {
                  background = widget.appearance.textColor(context.tokens).withValues(alpha: 0.06);
                } else {
                  background = null;
                }

                return AnimatedContainer(
                  width: double.infinity,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  color: background ?? Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
                  child: _buildContent(context, theme, highlightColor),
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