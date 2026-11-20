import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/dimens.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';
import '../../dictionary/widgets/glossary_entry_sheet.dart';

/// Builds the consolidated inline text-selection toolbar for Book & Article readers.
///
/// Positioned directly above/below the selected text range via
/// [TextSelectionToolbarLayoutDelegate] and exposes inline highlight swatches,
/// optional Clear/Note actions, Define, Copy, and Share in one floating pill.
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
  final tokens = context.tokens;
  const quickSwatchIndices = <int>[0, 2, 4, 1];

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
    child: Material(
      color: tokens.surface,
      elevation: 6,
      shadowColor: tokens.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        side: BorderSide(color: tokens.surfaceBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 16).clamp(200.0, 520.0),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final idx in quickSwatchIndices)
                Tooltip(
                  message: 'Highlight (${HighlightPalette.nameFor(idx)})',
                  child: Semantics(
                    label: 'Highlight ${HighlightPalette.nameFor(idx)}',
                    button: true,
                    child: InkResponse(
                      onTap: () => triggerHighlight(idx),
                      radius: 14,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: HighlightPalette.colorFor(idx),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tokens.surfaceBorder,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (onClearHighlight != null)
                _InlineToolbarIconButton(
                  icon: Icons.format_color_reset_rounded,
                  tooltip: 'Clear highlight',
                  onTap: () {
                    selectableRegionState.hideToolbar();
                    if (selectedText.isNotEmpty) {
                      onClearHighlight(selectedText, pageNum);
                    }
                  },
                ),
              Container(
                width: 1,
                height: 18,
                color: tokens.surfaceBorder,
              ),
              if (onNote != null)
                _InlineToolbarIconButton(
                  icon: Icons.edit_note_rounded,
                  tooltip: 'Note',
                  onTap: () {
                    selectableRegionState.hideToolbar();
                    if (selectedText.isNotEmpty) {
                      onNote(selectedText, pageNum);
                    }
                  },
                ),
              _InlineToolbarIconButton(
                icon: Icons.menu_book_rounded,
                tooltip: 'Define',
                onTap: () {
                  selectableRegionState.hideToolbar();
                  final words = selectedText
                      .split(RegExp(r'\s+'))
                      .map(
                        (w) => w.replaceAll(
                          RegExp(
                            r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]''',
                          ),
                          '',
                        ),
                      )
                      .where((w) => w.isNotEmpty)
                      .toList();
                  final lookupWord =
                      words.isNotEmpty ? words.first : selectedText;
                  GlossaryEntrySheet.show(context, word: lookupWord);
                },
              ),
              _InlineToolbarIconButton(
                icon: Icons.copy_rounded,
                tooltip: 'Copy',
                onTap: () {
                  selectableRegionState.hideToolbar();
                  if (selectedText.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: selectedText));
                  }
                },
              ),
              _InlineToolbarIconButton(
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
        ),
      ),
    ),
  );
}

class _InlineToolbarIconButton extends StatelessWidget {
  const _InlineToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: InkResponse(
          onTap: onTap,
          radius: 16,
          child: SizedBox.square(
            dimension: 28,
            child: Center(
              child: Icon(
                icon,
                size: 17,
                color: tokens.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
