import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../../../shared/ui/language_meta.dart';
import '../models/wftw_index_entry.dart';
import '../services/wftw_index_service.dart';
import '../widgets/article_row.dart';

/// Multi-language articles browser: lists the combined article archive
/// (English + seeded CFC languages), filtered by the app-wide shared
/// [LibraryLanguagesController] so language selection stays centralized at the
/// Library level. No per-screen language picker. Grouped by year with a
/// client-side title search.
class ArticleBrowserScreen extends StatefulWidget {
  final WftwIndexLoader? loader;
  final LibraryLanguagesController? langController;

  const ArticleBrowserScreen({super.key, this.loader, this.langController});

  @override
  State<ArticleBrowserScreen> createState() => _ArticleBrowserScreenState();
}

class _ArticleBrowserScreenState extends State<ArticleBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final LibraryLanguagesController _langController;

  List<WftwIndexEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  Timer? _searchDebounceTimer;
  String? _lastFilterQuery;
  Set<String>? _lastFilterLangs;
  List<WftwIndexEntry>? _lastFiltered;
  Map<int, List<WftwIndexEntry>>? _cachedByYear;

  @override
  void initState() {
    super.initState();
    _langController = (widget.langController ?? LibraryLanguagesController.instance)
      ..addListener(_onLanguagesChanged);
    _loadEntries();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _langController.removeListener(_onLanguagesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLanguagesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? WftwIndexService().getArticlesIndex;
      final entries = await loader();
      if (!mounted) return;
      final languages = <String>{};
      for (final e in entries) {
        if (e.lang.isNotEmpty) languages.add(e.lang);
      }
      _langController.announceLanguages(languages);
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// All entries, filtered by the shared library language selection.
  List<WftwIndexEntry> get _langFiltered {
    final state = _langController.state;
    if (state.isAllLanguages) return _entries;
    return _entries.where((e) => state.includes(e.lang)).toList();
  }

  List<WftwIndexEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    final langFiltered = _langFiltered;
    if (q.isEmpty) return langFiltered;
    return langFiltered
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  Map<String, int> get _languageCounts {
    final counts = <String, int>{'All': _entries.length};
    for (final e in _entries) {
      final code = LanguageMeta.canonicalCode(e.lang);
      if (code.isEmpty || code == 'all') continue;
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  }

  String get _countLabel {
    final state = _langController.state;
    if (state.isAllLanguages) return '${_langFiltered.length} articles • All';
    if (state.selectedLanguages.length == 1) {
      return '${_langFiltered.length} articles • ${LanguageMeta.fromCode(state.selectedLanguages.first).englishName}';
    }
    return '${_langFiltered.length} articles • ${state.selectedLanguages.length} languages';
  }

  void _openArticle(WftwIndexEntry entry) {
    final lang = entry.lang == 'en' ? null : entry.lang;
    final uri = lang != null
        ? Uri(path: '/article/${entry.id}', queryParameters: {'lang': lang}).toString()
        : '/article/${entry.id}';
    context.push(
      uri,
      extra: {'title': entry.title, if (lang != null) 'lang': lang},
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: tokens.background,
        foregroundColor: tokens.onSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Articles', style: TextStyle(fontWeight: FontWeight.bold)),
            if (!_loading && _error == null)
              Text(
                _countLabel,
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted, size: 21),
            tooltip: 'Refresh articles',
            onPressed: _loadEntries,
          ),
        ],
      ),
      body: _buildBody(tokens),
    );
  }

  Widget _buildBody(AppTokens tokens) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: tokens.accent),
            const SizedBox(height: 16),
            Text('Loading articles...',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: tokens.onSurfaceMuted, size: 40),
              const SizedBox(height: 12),
              Text(
                'Could not load articles.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadEntries,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.surfaceVariant,
                  foregroundColor: tokens.onSurface,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final byYear = _resolveByYear();

    return MaxWidthBox(
      maxWidth: 1080,
      child: RefreshIndicator(
        onRefresh: _loadEntries,
        color: tokens.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _buildLanguageFilter(tokens),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  _searchDebounceTimer?.cancel();
                  _searchDebounceTimer =
                      Timer(const Duration(milliseconds: 250), () {
                    if (mounted) {
                      setState(() => _query = value);
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search articles...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchDebounceTimer?.cancel();
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: tokens.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: tokens.surfaceBorder),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          if (byYear.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No articles match "${_query.trim()}".',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                ),
              ),
            )
          else
            for (final yearGroup in byYear.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${yearGroup.key}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: tokens.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${yearGroup.value.length}',
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ArticleRow(
                    entry: yearGroup.value[index],
                    onTap: () => _openArticle(yearGroup.value[index]),
                  ),
                  childCount: yearGroup.value.length,
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    ),
    );
  }

  Widget _buildLanguageFilter(AppTokens tokens) {
    final langState = _langController.state;
    if (langState.availableLanguages.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LanguageDropdown(
        selectedLanguages: langState.selectedLanguages,
        availableLanguages: langState.availableLanguages,
        itemCounts: _languageCounts,
        onLanguagesSelected: _langController.selectLanguages,
        itemNoun: 'articles',
        headerTitle: 'Articles by Language',
      ),
    );
  }

  Map<int, List<WftwIndexEntry>> _resolveByYear() {
    final filtered = _filtered;
    final langs = _langController.state.selectedLanguages;
    if (_cachedByYear != null &&
        _lastFilterQuery == _query &&
        setEquals(_lastFilterLangs, langs) &&
        _lastFiltered == _entries) {
      return _cachedByYear!;
    }
    _lastFilterQuery = _query;
    _lastFilterLangs = Set.of(langs);
    _lastFiltered = _entries;
    _cachedByYear = groupByYear(filtered);
    return _cachedByYear!;
  }
}