import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/book_reader_controller.dart';
import '../models/book_highlight.dart';

/// Modal sheet or dialog displaying all highlights and notes for a book.
///
/// All data reads/writes route through [BookReaderController] (AGENTS.md
/// "explicit layer boundaries") rather than reaching into services directly.
class BookHighlightsSheet extends StatefulWidget {
  final BookReaderController controller;
  final String bookId;
  final String bookTitle;
  final void Function(int pageNumber) onSelectPage;

  const BookHighlightsSheet({
    super.key,
    required this.controller,
    required this.bookId,
    required this.bookTitle,
    required this.onSelectPage,
  });

  static Future<void> show(
    BuildContext context, {
    required BookReaderController controller,
    required String bookId,
    required String bookTitle,
    required void Function(int pageNumber) onSelectPage,
  }) async {
    final screen = ScreenClass.of(context);
    if (screen.isCompact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => BookHighlightsSheet(
          controller: controller,
          bookId: bookId,
          bookTitle: bookTitle,
          onSelectPage: onSelectPage,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
            child: BookHighlightsSheet(
              controller: controller,
              bookId: bookId,
              bookTitle: bookTitle,
              onSelectPage: onSelectPage,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<BookHighlightsSheet> createState() => _BookHighlightsSheetState();
}

class _BookHighlightsSheetState extends State<BookHighlightsSheet> {
  List<BookHighlight> _highlights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  Future<void> _loadHighlights() async {
    final list = await widget.controller.getHighlightsForBook(widget.bookId);
    if (mounted) {
      setState(() {
        _highlights = list;
        _isLoading = false;
      });
    }
  }

  Color _highlightColor(int colorIndex) {
    switch (colorIndex) {
      case 1:
        return const Color(0xFF81C784); // Green
      case 2:
        return const Color(0xFF64B5F6); // Blue
      case 3:
        return const Color(0xFFF48FB1); // Pink
      case 0:
      default:
        return const Color(0xFFFFD54F); // Amber / Yellow
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: tokens.accent, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Highlights & Notes',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: tokens.surfaceBorder, height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _highlights.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border_rounded, size: 44, color: tokens.onSurfaceMuted),
                            const SizedBox(height: 10),
                            Text(
                              'No highlights yet',
                              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Select any text in the book to highlight it.',
                              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _highlights.length,
                        separatorBuilder: (_, __) => Divider(color: tokens.surfaceBorder, height: 16),
                        itemBuilder: (context, index) {
                          final h = _highlights[index];
                          final c = _highlightColor(h.color);

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onSelectPage(h.pageNumber);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 4,
                                    height: 36,
                                    margin: const EdgeInsets.only(top: 2, right: 12),
                                    decoration: BoxDecoration(
                                      color: c,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '“${h.text}”',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: tokens.onSurface,
                                            fontSize: 14,
                                            height: 1.45,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Page ${h.pageNumber}',
                                          style: TextStyle(
                                            color: tokens.accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 18, color: tokens.onSurfaceMuted),
                                    tooltip: 'Delete highlight',
                                    onPressed: () async {
                                      await widget.controller.deleteHighlight(h.id);
                                      _loadHighlights();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
