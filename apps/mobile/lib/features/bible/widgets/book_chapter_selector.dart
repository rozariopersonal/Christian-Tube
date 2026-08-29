import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_book.dart';

class BookChapterSelector extends StatefulWidget {
  final String currentBook;
  final int currentChapter;
  final Function(String book, int chapter) onSelection;
  final String Function(String canonicalBook, int bookNumber)? displayNameOf;

  const BookChapterSelector({
    super.key,
    required this.currentBook,
    required this.currentChapter,
    required this.onSelection,
    this.displayNameOf,
  });

  @override
  State<BookChapterSelector> createState() => _BookChapterSelectorState();
}

class _BookChapterSelectorState extends State<BookChapterSelector> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _selectedBook;
  late int _selectedChapter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedBook = widget.currentBook;
    _selectedChapter = widget.currentChapter;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.tokens.onSurfaceDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: context.tokens.onSurfaceMuted,
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: 'BOOKS'),
              Tab(text: 'CHAPTERS'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Books List
                ListView.builder(
                  itemCount: bibleBooks.length,
                  itemBuilder: (context, index) {
                    final book = bibleBooks.keys.elementAt(index);
                    final bookNumber = index + 1;
                    final isSelected = book == _selectedBook;
                    final displayName =
                        widget.displayNameOf?.call(book, bookNumber) ?? book;
                    return ListTile(
                      title: Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedBook = book;
                        });
                        _tabController.animateTo(1);
                      },
                    );
                  },
                ),
                // Chapters Grid
                GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: bibleBooks[_selectedBook] ?? 1,
                  itemBuilder: (context, index) {
                    final chapter = index + 1;
                    final isSelected = chapter == _selectedChapter && _selectedBook == widget.currentBook;
                    return InkWell(
                      onTap: () {
                        widget.onSelection(_selectedBook, chapter);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected 
                            ? theme.colorScheme.primary 
                            : context.tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          chapter.toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected 
                              ? theme.colorScheme.onPrimary 
                              : context.tokens.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
