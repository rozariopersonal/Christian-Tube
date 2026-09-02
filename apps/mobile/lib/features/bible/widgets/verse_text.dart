import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../dictionary/services/dictionary_service.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';
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
  String _lastLookedUpWord = '';
  bool _isHovering = false;

  Future<void> _performAutoLookup(String word, dynamic selectableRegionState) async {
    if (word.isEmpty) return;
    try {
      final service = DictionaryService();
      final cleanWord = service.cleanWord(word);
      if (cleanWord.isEmpty) return;
      
      final results = await service.lookupWord(cleanWord);
      
      if (mounted && _lastLookedUpWord == word && results.isNotEmpty) {
        selectableRegionState.hideToolbar();
        InlineDictionaryPopover.show(context, word: word);
      }
    } catch (_) {}
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

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          color: widget.isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : widget.isHighlighted
                  ? theme.colorScheme.primaryContainer
                  : _isHovering
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                      : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Expanded(
              child: SelectionArea(
                contextMenuBuilder: (context, selectableRegionState) {
                  String selectedText = '';
                  try {
                    final dynamic dyn = selectableRegionState;
                    final dynamic content = dyn.getSelectedContent();
                    if (content != null && content.plainText != null && (content.plainText as String).trim().isNotEmpty) {
                      selectedText = (content.plainText as String).trim();
                    }
                  } catch (_) {}

                  if (selectedText.isEmpty) {
                    final val = selectableRegionState.textEditingValue;
                    selectedText = (val.selection.isValid && !val.selection.isCollapsed)
                        ? val.selection.textInside(val.text).trim()
                        : val.text.trim();
                  }

                  final words = selectedText
                      .split(RegExp(r'\s+'))
                      .map((w) => w.replaceAll(RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''), ''))
                      .where((w) => w.isNotEmpty)
                      .toList();
                  final lookupWord = words.isNotEmpty ? words.first : selectedText;

                  if (lookupWord.isNotEmpty && lookupWord != _lastLookedUpWord) {
                    _lastLookedUpWord = lookupWord;
                    _performAutoLookup(lookupWord, selectableRegionState);
                  }

                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: selectableRegionState.contextMenuAnchors,
                    buttonItems: [
                      ContextMenuButtonItem(
                        label: 'Define',
                        onPressed: () {
                          selectableRegionState.hideToolbar();
                          InlineDictionaryPopover.show(context, word: lookupWord);
                        },
                      ),
                      ContextMenuButtonItem(
                        label: 'Copy',
                        onPressed: () {
                          selectableRegionState.copySelection(SelectionChangedCause.toolbar);
                        },
                      ),
                    ],
                  );
                },
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${widget.verse.number} ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.tokens.onSurfaceMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: widget.fontSize * 0.7,
                        ),
                      ),
                      TextSpan(
                        text: widget.verse.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          fontSize: widget.fontSize,
                          color: widget.verse.isSecondary
                              ? context.tokens.onSurfaceMuted
                              : null,
                        ),
                      ),
                      if (widget.refCount > 0)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
                            child: Icon(
                              Icons.link_rounded,
                              size: widget.fontSize * 0.6,
                              color: theme.colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      if (widget.commentaryCount > 0)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
                            child: Icon(
                              Icons.menu_book_rounded,
                              size: widget.fontSize * 0.6,
                              color: theme.colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
