import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/wftw_index_entry.dart';
import '../services/wftw_index_service.dart';
import '../widgets/article_row.dart';

/// Multi-language articles browser: picks a language (English + the seeded
/// CFC languages), then browses that language's Word-for-the-Week archive
/// grouped by year, with a client-side title search.
class ArticleBrowserScreen extends StatefulWidget {
  final ArticlesLoader? loader;
  final ArticlesLanguagesLoader? languagesLoader;
  final String initialLang;

  const ArticleBrowserScreen({
    super.key,
    this.loader,
    this.languagesLoader,
    this.initialLang = 'en',
  });

  @override
  State<ArticleBrowserScreen> createState() => _ArticleBrowserScreenState();
}

class _ArticleBrowserScreenState extends State<ArticleBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _lang;
  List<ArticleLanguage> _languages = const [];
  List<WftwIndexEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _lang = widget.initialLang;
    _loadLanguages();
    _loadEntries(_lang);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLanguages() async {
    try {
      final loader = widget.languagesLoader ?? WftwIndexService().getLanguages;
      final languages = await loader();
      if (!mounted) return;
      setState(() => _languages = languages);
    } catch (e) {
      debugPrint('Articles languages unavailable: $e');
    }
  }

  Future<void> _loadEntries(String lang) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? WftwIndexService().getLanguageArticles;
      final entries = await loader(lang);
      if (!mounted) return;
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

  void _selectLanguage(String lang) {
    if (lang == _lang) return;
    setState(() => _lang = lang);
    _loadEntries(lang);
  }

  String get _langName {
    for (final l in _languages) {
      if (l.code == _lang) return l.name;
    }
    return _lang.toUpperCase();
  }

  List<WftwIndexEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  void _openArticle(WftwIndexEntry entry) {
    context.push(
      '/article/${entry.id}',
      extra: {'title': entry.title, 'lang': _lang},
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.onSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Articles', style: TextStyle(fontWeight: FontWeight.bold)),
            if (!_loading && _error == null)
              Text(
                '${_entries.length} articles • $_langName',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_languages.isNotEmpty) _buildLanguageBar(tokens),
          Expanded(child: _buildBody(tokens)),
        ],
      ),
    );
  }

  Widget _buildLanguageBar(AppTokens tokens) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final lang in _languages)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(lang.name),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  color: _lang == lang.code ? tokens.onSurface : tokens.onSurfaceMuted,
                  fontWeight: _lang == lang.code ? FontWeight.w600 : FontWeight.w400,
                ),
                selected: _lang == lang.code,
                selectedColor: tokens.accent.withValues(alpha: 0.2),
                backgroundColor: tokens.surfaceVariant,
                side: BorderSide(color: tokens.surfaceBorder),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _selectLanguage(lang.code),
              ),
            ),
        ],
      ),
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
                'Could not load articles for $_langName.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _loadEntries(_lang),
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

    final filtered = _filtered;
    final byYear = groupByYear(filtered);

    return MaxWidthBox(
      maxWidth: 1080,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search articles...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
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
                    langLabel: _lang == 'en' ? null : _langName,
                    onTap: () => _openArticle(yearGroup.value[index]),
                  ),
                  childCount: yearGroup.value.length,
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}