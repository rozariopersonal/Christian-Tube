import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_verse.dart';

class VerseText extends StatefulWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final double fontSize;
  final int refCount;
  final int commentaryCount;

  const VerseText({
    super.key,
    required this.verse,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.fontSize = 18.0,
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
            return AnimatedContainer(
              width: double.infinity,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              color: widget.isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : widget.isHighlighted
                      ? theme.colorScheme.primaryContainer
                      : isHovering
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                          : Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
              child: _buildContent(context, theme),
            );
          },
        ),
      ),
    );
  }
  Widget _buildContent(BuildContext context, ThemeData theme) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${widget.verse.number}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.tokens.onSurfaceMuted,
              fontWeight: FontWeight.bold,
              fontSize: widget.fontSize * 0.7,
            ),
          ),
          if (widget.refCount > 0)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 2.0, right: 1.0, top: 2.0),
                child: Icon(
                  Icons.link_rounded,
                  size: widget.fontSize * 0.45,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
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
                  size: widget.fontSize * 0.45,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ),
          TextSpan(
            text: ' ${widget.verse.text}',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              fontSize: widget.fontSize,
              color: widget.verse.isSecondary
                  ? context.tokens.onSurfaceMuted
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
