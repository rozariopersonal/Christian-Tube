import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../books/models/book.dart';
import '../controllers/downloads_controller.dart';
import 'common/download_action_button.dart';
import 'common/download_bundle_card.dart';
import 'common/download_empty_state.dart';
import 'common/download_filter_bar.dart';
import 'common/download_item_tile.dart';

class BooksTab extends StatefulWidget {
  final DownloadsController controller;

  const BooksTab({
    super.key,
    required this.controller,
  });

  @override
  State<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<BooksTab> {
  late final TextEditingController _searchController;
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = {};
  String _sortBy = 'default'; // 'default', 'title', 'author', 'installed'

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.state.bookSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final itemExtent = (124.0 * textScale.clamp(1.0, 2.2)).toDouble();

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        var books = state.books.toList();

        // Extract available languages for filter chips
        final languages = {'All'};
        for (final b in state.books) {
          if (b.language.trim().isNotEmpty) {
            languages.add(b.language.trim());
          }
        }

        // Language Filter
        if (state.bookLanguageFilter != 'All') {
          books = books
              .where((b) =>
                  b.language.toLowerCase() ==
                  state.bookLanguageFilter.toLowerCase())
              .toList();
        }

        // Search Filter
        if (state.bookSearch.trim().isNotEmpty) {
          final q = state.bookSearch.trim().toLowerCase();
          books = books
              .where((b) =>
                  b.title.toLowerCase().contains(q) ||
                  b.author.toLowerCase().contains(q) ||
                  b.subject.toLowerCase().contains(q))
              .toList();
        }

        // Installed Only Filter
        if (state.onlyInstalled) {
          books = books
              .where((b) => widget.controller.isBookInstalled(b.id))
              .toList();
        }

        // Sorting
        if (_sortBy == 'title') {
          books.sort((a, b) => a.title.compareTo(b.title));
        } else if (_sortBy == 'author') {
          books.sort((a, b) => a.author.compareTo(b.author));
        } else if (_sortBy == 'installed') {
          books.sort((a, b) {
            final aInst = widget.controller.isBookInstalled(a.id) ? 0 : 1;
            final bInst = widget.controller.isBookInstalled(b.id) ? 0 : 1;
            return aInst.compareTo(bInst);
          });
        }

        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        // Keep local search controller in sync if cleared externally
        if (_searchController.text != state.bookSearch) {
          _searchController.value = TextEditingValue(
            text: state.bookSearch,
            selection: TextSelection.collapsed(offset: state.bookSearch.length),
          );
        }

        return MaxWidthBox(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // 1. Complete Library Bundle Card
                        _buildLibraryBundleCard(context, tokens),
                        const SizedBox(height: 16),

                        // 2. Offline Articles Section Card
                        _buildArticlesCard(context, tokens),
                        const SizedBox(height: 20),

                        // 3. Search and Language Filter Bar
                        DownloadFilterBar(
                          searchController: _searchController,
                          searchHint: 'Search books by title, author, or topic…',
                          onSearchChanged: widget.controller.setBookSearch,
                          categories: languages,
                          selectedCategory: state.bookLanguageFilter,
                          onCategorySelected: widget.controller.setBookLanguageFilter,
                          onlyInstalled: state.onlyInstalled,
                          onToggleOnlyInstalled: widget.controller.toggleOnlyInstalled,
                        ),
                        const SizedBox(height: 16),

                        // 4. Section Header with Sort & Multi-Select
                        Row(
                          children: [
                            Text(
                              _isMultiSelect
                                  ? 'SELECT BOOKS (${_selectedIds.length})'
                                  : 'INDIVIDUAL BOOKS (${books.length})',
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.sort_rounded, size: 18, color: tokens.onSurfaceMuted),
                              tooltip: 'Sort books',
                              onSelected: (val) => setState(() => _sortBy = val),
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'default', child: Text('Default Order')),
                                const PopupMenuItem(value: 'title', child: Text('Title (A–Z)')),
                                const PopupMenuItem(value: 'author', child: Text('Author (A–Z)')),
                                const PopupMenuItem(value: 'installed', child: Text('Installed First')),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isMultiSelect = !_isMultiSelect;
                                  if (!_isMultiSelect) _selectedIds.clear();
                                });
                              },
                              icon: Icon(_isMultiSelect ? Icons.close : Icons.checklist_rounded, size: 16),
                              label: Text(_isMultiSelect ? 'Done' : 'Select'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                foregroundColor: tokens.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ]),
                    ),
                  ),

              // Empty state or Books Grid / List
              if (books.isEmpty)
                SliverToBoxAdapter(
                  child: DownloadEmptyState(
                    title: 'No books found',
                    subtitle: 'Try adjusting your search query or language filter.',
                    onResetFilters: () {
                      _searchController.clear();
                      widget.controller.setBookSearch('');
                      widget.controller.setBookLanguageFilter('All');
                      if (widget.controller.state.onlyInstalled) {
                        widget.controller.toggleOnlyInstalled();
                      }
                    },
                  ),
                )
              else if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: itemExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildBookItem(context, books[index], tokens),
                      childCount: books.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildBookItem(context, books[index], tokens),
                      ),
                      childCount: books.length,
                    ),
                  ),
                ),
              if (_isMultiSelect && _selectedIds.isNotEmpty)
                const SliverToBoxAdapter(child: SizedBox(height: 80))
              else
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
          if (_isMultiSelect && _selectedIds.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildBatchActionBar(tokens, books),
            ),
        ],
      ),
    );
  },
);
  }

  Widget _buildLibraryBundleCard(BuildContext context, AppTokens tokens) {
    final state = widget.controller.state;
    final isInstalled = state.booksBundleInstalled;
    final isDownloading = state.isBooksBundleDownloading;
    final progress = state.booksBundleProgress;

    return DownloadBundleCard(
      icon: Icons.auto_stories_rounded,
      title: 'Complete Books & Commentaries',
      subtitle: 'Zac Poonen Library (181 Books across 7 Languages • ~13.4 MB)',
      description:
          'Downloading this single compact package unlocks all 181 books for offline reading AND links thousands of verse-by-verse commentary expositions directly into the Bible Study screen.',
      isDownloading: isDownloading,
      progress: progress,
      progressLabel: 'Downloading library: ${(progress * 100).toStringAsFixed(0)}%',
      statusWidget: isInstalled
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: tokens.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Full Library & Commentaries Active',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ],
            )
          : null,
      secondaryAction: isInstalled
          ? OutlinedButton(
              onPressed: widget.controller.downloadBooksBundle,
              child: const Text('Re-sync'),
            )
          : null,
      actionWidget: isInstalled
          ? IconButton(
              icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted),
              tooltip: 'Delete complete books bundle',
              onPressed: () => _confirmDeleteBooksBundle(context),
            )
          : SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.controller.downloadBooksBundle,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download Complete Books & Commentaries (~13.4 MB)'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmDeleteBooksBundle(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Books Library?'),
        content: const Text(
          'This will remove all 181 offline books and commentaries from local storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.controller.deleteBooksBundle();
    }
  }

  Widget _buildArticlesCard(BuildContext context, AppTokens tokens) {
    final state = widget.controller.state;
    final installed = state.installedArticleLanguages;
    final downloading = state.downloadingArticleLanguages;

    const articlePackages = [
      ('en', 'English (1,329 articles • ~5.5 MB)'),
      ('ta', 'Tamil (661 articles • ~4.1 MB)'),
      ('hi', 'Hindi (424 articles • ~2.1 MB)'),
      ('te', 'Telugu (820 articles • ~4.0 MB)'),
      ('kn', 'Kannada (748 articles • ~4.1 MB)'),
      ('ml', 'Malayalam (685 articles • ~4.1 MB)'),
      ('de', 'German (1,043 articles • ~4.8 MB)'),
      ('ro', 'Romanian (729 articles • ~3.1 MB)'),
      ('fr', 'French (365 articles • ~1.6 MB)'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_rounded, color: tokens.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Offline Articles Packages',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Precompiled topical teaching articles by Zac Poonen for zero-latency offline reading.',
            style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          // Bounded Column / Wrap prevents horizontal RenderFlex overflow
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final pkg in articlePackages)
                    _buildArticlePackageTile(
                      context,
                      maxWidth: constraints.maxWidth,
                      code: pkg.$1,
                      label: pkg.$2,
                      isInstalled: installed.contains(pkg.$1),
                      isDownloading: downloading.contains(pkg.$1),
                      tokens: tokens,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildArticlePackageTile(
    BuildContext context, {
    required double maxWidth,
    required String code,
    required String label,
    required bool isInstalled,
    required bool isDownloading,
    required AppTokens tokens,
  }) {
    final itemWidth = maxWidth < 400 ? double.infinity : (maxWidth - 10) / 2;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: itemWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Row(
          children: [
            if (isDownloading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              )
            else
              Icon(
                isInstalled ? Icons.check_circle : Icons.download_rounded,
                size: 16,
                color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (isDownloading)
              Text(
                'Downloading…',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (isInstalled)
              InkWell(
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Remove $label?'),
                      content: const Text('Offline articles for this language will be deleted.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await widget.controller.deleteArticlesLanguage(code);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: tokens.onSurfaceMuted),
                ),
              )
            else
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => widget.controller.downloadArticlesLanguage(code),
                child: const Text('Download', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookItem(BuildContext context, Book book, AppTokens tokens) {
    final isInstalled = widget.controller.isBookInstalled(book.id);
    final isDownloading = widget.controller.isBookDownloading(book.id);
    final isSelected = _selectedIds.contains(book.id);

    return InkWell(
      onTap: _isMultiSelect
          ? () {
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(book.id);
                } else {
                  _selectedIds.add(book.id);
                }
              });
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: DownloadItemTile(
        leading: _isMultiSelect
            ? Checkbox(
                value: isSelected,
                activeColor: tokens.accent,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds.add(book.id);
                    } else {
                      _selectedIds.remove(book.id);
                    }
                  });
                },
              )
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInstalled ? tokens.accent.withValues(alpha: 0.15) : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isInstalled ? Icons.check_circle : Icons.book_rounded,
                  color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                  size: 20,
                ),
              ),
        title: book.title,
        subtitle: '${book.author} • ${book.totalPages} pages • ${book.language}',
        description: book.downloadSizeFormatted.isNotEmpty
            ? 'Size: ${book.downloadSizeFormatted}'
            : null,
        isDownloading: isDownloading,
        trailing: _isMultiSelect
            ? const SizedBox.shrink()
            : isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : DownloadActionButton(
                    isInstalled: isInstalled,
                    isDownloading: false,
                    onDownload: () => widget.controller.downloadSingleBook(
                      book.id,
                      language: book.language,
                    ),
                    onDelete: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Remove ${book.title}?'),
                          content: const Text('This book will be removed from offline storage.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await widget.controller.deleteBook(book.id);
                      }
                    },
                  ),
      ),
    );
  }

  Widget _buildBatchActionBar(AppTokens tokens, List<Book> books) {
    final selectedBooks = books.where((b) => _selectedIds.contains(b.id)).toList();
    final notInstalled = selectedBooks.where((b) => !widget.controller.isBookInstalled(b.id)).toList();
    final installed = selectedBooks.where((b) => widget.controller.isBookInstalled(b.id)).toList();

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: tokens.surfaceVariant,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedIds.length} books selected',
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${notInstalled.length} to download • ${installed.length} installed',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (notInstalled.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  final list = notInstalled.map((b) => (id: b.id, language: b.language)).toList();
                  widget.controller.batchDownloadBooks(list);
                  setState(() {
                    _isMultiSelect = false;
                    _selectedIds.clear();
                  });
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('Get (${notInstalled.length})'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.background,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (installed.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Selected Books?'),
                      content: Text('Delete ${installed.length} selected books from local storage?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await widget.controller.batchDeleteBooks(installed.map((b) => b.id).toList());
                    setState(() {
                      _isMultiSelect = false;
                      _selectedIds.clear();
                    });
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text('Delete (${installed.length})'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
