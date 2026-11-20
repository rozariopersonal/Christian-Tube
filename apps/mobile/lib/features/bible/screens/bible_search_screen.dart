import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/bible_version_pill.dart';
import '../../books/services/scripture_ref_parser.dart';
import '../controllers/bible_search_controller.dart';
import '../models/bible_book.dart';
import '../models/bible_reference.dart';
import '../models/bible_search_hit.dart';
import '../services/bible_passage_navigator.dart';

/// Full-screen Bible search and results view triggered on explicit submit,
/// displaying matches in the currently active Bible version with an inline
/// version switcher.
class BibleSearchScreen extends StatefulWidget {
  final String? initialQuery;
  final String? versionId;
  final String? currentBook;
  final bool popWithResult;
  final BibleSearchController? controller;

  const BibleSearchScreen({
    super.key,
    this.initialQuery,
    this.versionId,
    this.currentBook,
    this.popWithResult = false,
    this.controller,
  });

  @override
  State<BibleSearchScreen> createState() => _BibleSearchScreenState();
}

class _BibleSearchScreenState extends State<BibleSearchScreen> {
  late final BibleSearchController _controller;
  late final bool _ownsController;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        BibleSearchController(
          versionId: widget.versionId,
          currentBook: widget.currentBook,
        );
    final seed = widget.initialQuery?.trim() ?? '';
    _textController = TextEditingController(text: seed);
    _controller.addListener(_onStateChanged);
    if (seed.isNotEmpty) {
      Future.microtask(() => _controller.search(seed));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    if (_ownsController) _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _submitSearch([String? raw]) {
    _controller.search(raw ?? _textController.text);
  }

  void _openReference(BibleReference ref) {
    if (widget.popWithResult) {
      Navigator.of(context).pop(ref);
      return;
    }
    BiblePassageNavigator.instance.navigateTo(ref, context: context);
  }

  void _openHit(BibleSearchHit hit) {
    final chapter = hit.chapter;
    final verse = hit.verse;
    if (chapter == null || verse == null) return;
    final bookNumber = hit.bookNumber ??
        (hit.canonicalBookKey != null
            ? bibleBooks.keys.toList().indexOf(hit.canonicalBookKey!) + 1
            : 1);
    _openReference(
      BibleReference(
        bookNumber: bookNumber,
        chapter: chapter,
        verse: verse,
        versionId: _controller.state.versionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final state = _controller.state;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _textController,
          autofocus: _textController.text.isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: _submitSearch,
          decoration: InputDecoration(
            hintText: 'Search verses, topics, or John 3:16...',
            border: InputBorder.none,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ),
        actions: [
          if (_textController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () {
                _textController.clear();
                _controller.clear();
              },
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Bible',
            onPressed: _submitSearch,
          ),
        ],
      ),
      body: MaxWidthBox(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterBar(
              scopes: _controller.availableScopes,
              selectedScope: state.scope,
              activeVersionId: state.versionId,
              currentBookLabel: widget.currentBook,
              onSelectScope: _controller.setScope,
              onSelectVersion: _controller.setVersion,
            ),
            if (state.directRef != null) ...[
              const SizedBox(height: 8),
              _DirectRefCard(
                directRef: state.directRef!,
                onTap: () => _openReference(
                  BibleReference(
                    bookNumber: state.directRef!.bookNumber,
                    chapter: state.directRef!.chapter,
                    verse: state.directRef!.startVerse,
                    versionId: state.versionId,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(child: _buildResultsBody(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsBody(BuildContext context, BibleSearchState state) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    if (state.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 48, color: tokens.onSurfaceDisabled),
              const SizedBox(height: 12),
              Text(
                'Type a phrase, story, or reference and tap Search\n(e.g. "jesus wept", "dry bones", "John 3:16")',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hits = state.filteredResults;
    if (hits.isEmpty && state.directRef == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 48, color: tokens.onSurfaceDisabled),
              const SizedBox(height: 12),
              Text(
                'No matching verses found for "${state.query}"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${hits.length} result${hits.length == 1 ? '' : 's'} · ${state.versionId.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ),
                if (state.isTranslating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: hits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _SearchResultTile(
              hit: hits[index],
              onTap: () => _openHit(hits[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<BibleSearchScope> scopes;
  final BibleSearchScope selectedScope;
  final String activeVersionId;
  final String? currentBookLabel;
  final ValueChanged<BibleSearchScope> onSelectScope;
  final ValueChanged<String> onSelectVersion;

  const _FilterBar({
    required this.scopes,
    required this.selectedScope,
    required this.activeVersionId,
    this.currentBookLabel,
    required this.onSelectScope,
    required this.onSelectVersion,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(
            child: BibleVersionPill(
              activeVersionId: activeVersionId,
              onSelectVersion: onSelectVersion,
            ),
          ),
          const SizedBox(width: 8),
          for (final scope in scopes) ...[
            ChoiceChip(
              label: Text(
                scope == BibleSearchScope.book &&
                        currentBookLabel != null &&
                        currentBookLabel!.isNotEmpty
                    ? currentBookLabel!
                    : scope.label,
              ),
              selected: scope == selectedScope,
              onSelected: (_) => onSelectScope(scope),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _DirectRefCard extends StatelessWidget {
  final ParsedScriptureRef directRef;
  final VoidCallback onTap;

  const _DirectRefCard({
    required this.directRef,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final refText =
        '${directRef.bookName} ${directRef.chapter}:${directRef.startVerse}';

    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.menu_book, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Go to $refText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Open passage directly in Bible reader',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final BibleSearchHit hit;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.hit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hit.displayReference,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: context.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (hit.isPassage) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Passage',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hit.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurface,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
