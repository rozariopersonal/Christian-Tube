import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';

/// Builds the reader's text-selection toolbar (Highlight / Define / Copy).
///
/// Pure presentational: extracts the selected plain text, wires the Define /
/// Copy actions, and delegates the Highlight action to [onHighlight].
Widget buildReaderSelectionToolbar(
  BuildContext context,
  SelectableRegionState selectableRegionState,
  int pageNum, {
  required void Function(String text, int pageNum) onHighlight,
}) {
  String selectedText = '';
  try {
    final dynamic dyn = selectableRegionState;
    final dynamic content = dyn.getSelectedContent();
    if (content != null && content.plainText != null && (content.plainText as String).trim().isNotEmpty) {
      selectedText = (content.plainText as String).trim();
    }
  } catch (_) {}

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: selectableRegionState.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        label: 'Highlight',
        onPressed: () {
          selectableRegionState.hideToolbar();
          if (selectedText.isNotEmpty) {
            onHighlight(selectedText, pageNum);
          }
        },
      ),
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
          selectableRegionState.hideToolbar();
          if (selectedText.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: selectedText));
          }
        },
      ),
    ],
  );
}
