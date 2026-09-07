import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/wftw_index_entry.dart';
import '../services/wftw_index_service.dart';

/// Browse the Word-for-the-Week article archive, grouped by year, with a
/// client-side title search. Rows open the article reader (`/article/:id`).
class WftwTeachingsScreen extends StatefulWidget {
  final WftwIndexLoader? loader;

  const WftwTeachingsScreen({super.key, this.loader});

  @override
  State<WftwTeachingsScreen> createState() => _WftwTeachingsScreenState();
}

class _WftwTeachingsScreenState extends State<WftwTeachingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<WftwIndexEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? WftwIndexService().getIndex;
      final entries = await loader();
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

  List<WftwIndexEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  void _openArticle(WftwIndexEntry entry) {
    context.push('/article/${entry.id}', extra: {'title': entry.title});
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
            const Text('Word for the Week', style: TextStyle(fontWeight: FontWeight.bold)),
            if (!_loading && _error == null)
              Text(
                '${_entries.length} teachings • Zac Poonen',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
          ],
        ),
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
            Text('Loading teachings...',
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
                'Could not load Word for the Week teachings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
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
                  hintText: 'Search teachings...',
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
                  'No teachings match "${_query.trim()}".',
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
                  (context, index) => _ArticleRow(
                    entry: yearGroup.value[index],
                    tokens: tokens,
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

class _ArticleRow extends StatelessWidget {
  final WftwIndexEntry entry;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _ArticleRow({
    required this.entry,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.surfaceBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatWftwDate(entry.date),
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: tokens.onSurfaceMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}