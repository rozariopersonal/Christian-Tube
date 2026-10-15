import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../books/models/book.dart';
import '../controllers/downloads_controller.dart';

class BooksTab extends StatelessWidget {
  final DownloadsController controller;

  const BooksTab({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
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
              .where((b) => controller.isBookInstalled(b.id))
              .toList();
        }

        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        return MaxWidthBox(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Complete Library Bundle Card
                    _buildLibraryBundleCard(tokens),
                    const SizedBox(height: 20),

                    // Search Field
                    TextField(
                      controller: TextEditingController(text: state.bookSearch)
                        ..selection = TextSelection.collapsed(offset: state.bookSearch.length),
                      onChanged: controller.setBookSearch,
                      style: TextStyle(color: tokens.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search books by title, author, or topic…',
                        hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
                        suffixIcon: state.bookSearch.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 18),
                                onPressed: () => controller.setBookSearch(''),
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: tokens.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Language & Installed Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final lang in languages)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(lang),
                                selected: state.bookLanguageFilter == lang,
                                onSelected: (_) => controller.setBookLanguageFilter(lang),
                                selectedColor: tokens.accent.withValues(alpha: 0.2),
                                checkmarkColor: tokens.accent,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: state.bookLanguageFilter == lang
                                      ? tokens.accent
                                      : tokens.onSurfaceMuted,
                                  fontWeight: state.bookLanguageFilter == lang
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          FilterChip(
                            avatar: Icon(Icons.download_done_rounded,
                                size: 16,
                                color: state.onlyInstalled ? tokens.accent : tokens.onSurfaceMuted),
                            label: const Text('Downloaded Only'),
                            selected: state.onlyInstalled,
                            onSelected: (_) => controller.toggleOnlyInstalled(),
                            selectedColor: tokens.accent.withValues(alpha: 0.2),
                            checkmarkColor: tokens.accent,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: state.onlyInstalled ? tokens.accent : tokens.onSurfaceMuted,
                              fontWeight: state.onlyInstalled ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section Header
                    Row(
                      children: [
                        Text(
                          'INDIVIDUAL BOOKS (${books.length})',
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${state.installedBookIds.length} Installed',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),

              // Books Grid / List (Lazy virtualized)
              if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 105,
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
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLibraryBundleCard(AppTokens tokens) {
    final state = controller.state;
    final isInstalled = state.booksBundleInstalled;
    final isDownloading = state.isBooksBundleDownloading;
    final progress = state.booksBundleProgress;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tokens.surface, tokens.surfaceElevated],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete Books & Commentaries',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Zac Poonen Library (181 Books across 7 Languages • ~13.4 MB)',
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Downloading this single compact package unlocks all 181 books for offline reading AND links thousands of verse-by-verse commentary expositions directly into the Bible Study screen.',
            style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (isInstalled)
            Row(
              children: [
                Icon(Icons.check_circle, color: tokens.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Full Library & Commentaries Active',
                    style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: controller.downloadBooksBundle,
                  child: const Text('Re-sync'),
                ),
              ],
            )
          else if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: tokens.surfaceVariant,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Downloading library: ${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.downloadBooksBundle,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download Complete Books & Commentaries (~13.4 MB)'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBookItem(BuildContext context, Book book, AppTokens tokens) {
    final isInstalled = controller.isBookInstalled(book.id);
    final isDownloading = controller.isBookDownloading(book.id);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${book.author} • ${book.totalPages} pages • ${book.language}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                ),
                if (book.downloadSizeFormatted.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Size: ${book.downloadSizeFormatted}',
                    style: TextStyle(color: tokens.onSurfaceDisabled, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isInstalled)
            IconButton(
              icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
              tooltip: 'Delete Book',
              onPressed: () async {
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
                  await controller.deleteBook(book.id);
                }
              },
            )
          else if (isDownloading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => controller.downloadSingleBook(book.id, language: book.language),
              child: const Text('Download', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
