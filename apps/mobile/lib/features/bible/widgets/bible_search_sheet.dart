import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/bible_version_pill.dart';
import '../controllers/bible_search_controller.dart';
import '../models/bible_search_hit.dart';

class BibleSearchSheet extends StatefulWidget {
  final String versionId;
  final String? currentBook;
  final BibleSearchController? controller;
  final void Function(String book, int chapter, int? verse) onJumpTo;

  const BibleSearchSheet({
    super.key,
    required this.versionId,
    this.currentBook,
    this.controller,
    required this.onJumpTo,
  });

  @override
  State<BibleSearchSheet> createState() => _BibleSearchSheetState();
}

class _BibleSearchSheetState extends State<BibleSearchSheet> {
  late final BibleSearchController _searchController;
  late final bool _ownsController;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _searchController = widget.controller ??
        BibleSearchController(
          versionId: widget.versionId,
          currentBook: widget.currentBook,
        );
    _searchController.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onStateChanged);
    if (_ownsController) _searchController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _submit([String? value]) {
    _searchController.search(value ?? _textController.text);
  }

  void _selectHit(BibleSearchHit hit) {
    final bookKey = hit.canonicalBookKey ?? hit.bookName;
    final chapter = hit.chapter;
    final verse = hit.verse;
    if (bookKey == null || chapter == null || verse == null) return;
    Navigator.pop(context);
    widget.onJumpTo(bookKey, chapter, verse);
  }

  void _openFullScreen() {
    final q = _textController.text.trim();
    final activeVer = _searchController.state.versionId;
    Navigator.pop(context);
    context.push(
      '/bible/search?q=${Uri.encodeComponent(q)}&version=${Uri.encodeComponent(activeVer)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final state = _searchController.state;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.onSurfaceDisabled,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Search Bible',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      BibleVersionPill(
                        activeVersionId: state.versionId,
                        onSelectVersion: _searchController.setVersion,
                      ),
                      const SizedBox(width: 4),
                      if (_textController.text.trim().length >= 2)
                        TextButton(
                          onPressed: _openFullScreen,
                          child: const Text('Full'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _submit,
                          decoration: InputDecoration(
                            hintText: 'Search verses, topics, or John 3:16…',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _textController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _textController.clear();
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submit,
                        child: const Text('Go'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildBody(scrollController)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    final state = _searchController.state;
    final theme = Theme.of(context);
    final tokens = context.tokens;

    if (state.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Type keywords, a story, or "John 3:16", then tap Go',
            style: TextStyle(color: tokens.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final hits = state.filteredResults;
    if (hits.isEmpty && state.directRef == null) {
      return Center(
        child: Text(
          'No matching verses found for "${state.query}"',
          style: TextStyle(color: tokens.onSurfaceMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: hits.length + (state.directRef != null ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (state.directRef != null && index == 0) {
          final ref = state.directRef!;
          return ListTile(
            dense: true,
            leading: Icon(Icons.menu_book, color: theme.colorScheme.primary),
            title: Text(
              'Go to ${ref.bookName} ${ref.chapter}:${ref.startVerse}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            subtitle: const Text('Open passage directly'),
            onTap: () {
              Navigator.pop(context);
              widget.onJumpTo(ref.bookName, ref.chapter, ref.startVerse);
            },
          );
        }

        final hit = hits[state.directRef != null ? index - 1 : index];
        return ListTile(
          dense: true,
          title: Text(
            hit.displayReference,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            hit.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.onSurface,
            ),
          ),
          trailing: hit.isPassage
              ? const Chip(
                  label: Text('Passage'),
                  visualDensity: VisualDensity.compact,
                )
              : null,
          onTap: () => _selectHit(hit),
        );
      },
    );
  }
}
