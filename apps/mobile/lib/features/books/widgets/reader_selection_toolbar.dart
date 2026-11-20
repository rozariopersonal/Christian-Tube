import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/ui/floating_selection_bar.dart';

/// Builds the inline text-selection toolbar for Book & Article readers.
///
/// Positioned directly above/below the selected text range via
/// [TextSelectionToolbarLayoutDelegate]. Renders the shared single-line
/// [FloatingSelectionBar]: the user's three most-used highlight colours (with a
/// chevron that expands the full palette) followed by Note, Define, Copy and
/// Share.
Widget buildReaderSelectionToolbar(
  BuildContext context,
  SelectableRegionState selectableRegionState,
  int pageNum, {
  required void Function(String text, int pageNum) onHighlight,
  void Function(String text, int pageNum, int colorIndex)? onHighlightWithColor,
  void Function(String text, int pageNum)? onClearHighlight,
  void Function(String text, int pageNum)? onNote,
  void Function(String text)? onShare,
}) {
  String selectedText = '';
  try {
    final dynamic dyn = selectableRegionState;
    final dynamic content = dyn.getSelectedContent();
    if (content != null &&
        content.plainText != null &&
        (content.plainText as String).trim().isNotEmpty) {
      selectedText = (content.plainText as String).trim();
    }
  } catch (_) {}

  final anchors = selectableRegionState.contextMenuAnchors;

  void triggerHighlight(int colorIndex) {
    selectableRegionState.hideToolbar();
    if (selectedText.isEmpty) return;
    if (onHighlightWithColor != null) {
      onHighlightWithColor(selectedText, pageNum, colorIndex);
    } else {
      onHighlight(selectedText, pageNum);
    }
  }

  return CustomSingleChildLayout(
    delegate: TextSelectionToolbarLayoutDelegate(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
    ),
    child: FloatingSelectionBar(
      onSwatch: triggerHighlight,
      hasHighlight: onClearHighlight != null,
      onClearHighlight: onClearHighlight == null
          ? null
          : () {
              selectableRegionState.hideToolbar();
              if (selectedText.isNotEmpty) {
                onClearHighlight(selectedText, pageNum);
              }
            },
      actions: [
        if (onNote != null)
          SelectionBarAction(
            icon: Icons.edit_note_rounded,
            tooltip: 'Note',
            onTap: () {
              selectableRegionState.hideToolbar();
              if (selectedText.isNotEmpty) onNote(selectedText, pageNum);
            },
          ),
        SelectionBarAction(
          icon: Icons.copy_rounded,
          tooltip: 'Copy',
          onTap: () {
            selectableRegionState.hideToolbar();
            if (selectedText.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: selectedText));
            }
          },
        ),
        SelectionBarAction(
          icon: Icons.ios_share_rounded,
          tooltip: 'Share',
          onTap: () {
            selectableRegionState.hideToolbar();
            if (selectedText.isEmpty) return;
            if (onShare != null) {
              onShare(selectedText);
            } else {
              Share.share(selectedText);
            }
          },
        ),
      ],
    ),
  );
}
