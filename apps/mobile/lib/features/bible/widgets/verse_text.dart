import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';
import '../models/bible_verse.dart';

class VerseText extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final double fontSize;

  const VerseText({
    super.key,
    required this.verse,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.fontSize = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (verse.isChapterHeader) {
      return Padding(
        padding: const EdgeInsets.only(top: 32.0, bottom: 16.0, left: 16.0, right: 16.0),
        child: Text(
          verse.chapterTitle ?? '',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : isHighlighted
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
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
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: selectableRegionState.contextMenuAnchors,
                    buttonItems: [
                      ContextMenuButtonItem(
                        label: 'Define',
                        onPressed: () {
                          selectableRegionState.hideToolbar();
                          final words = selectedText
                              .split(RegExp(r'\s+'))
                              .map((w) => w.replaceAll(RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''), ''))
                              .where((w) => w.isNotEmpty)
                              .toList();
                          final lookupWord = words.isNotEmpty ? words.first : selectedText;
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
                        text: '${verse.number} ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.tokens.onSurfaceMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize * 0.7,
                        ),
                      ),
                      TextSpan(
                        text: verse.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          fontSize: fontSize,
                          color: verse.isSecondary
                              ? context.tokens.onSurfaceMuted
                              : null,
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
    );
  }
}
