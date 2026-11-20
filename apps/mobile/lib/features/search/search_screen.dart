import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/models/short.dart';
import '../../shared/ui/bible_version_pill.dart';
import '../../shared/ui/search_video_card.dart';
import '../../core/config/app_config.dart';
import '../bible/models/bible_reference.dart';
import '../bible/models/bible_search_hit.dart';
import '../bible/services/bible_passage_navigator.dart';
import '../bible/services/bible_search_service.dart';
import '../bible/services/bible_settings_service.dart';
import '../engines/scripture/services/bible_download_manager.dart';

enum _GlobalSearchFilter { all, videos, bible }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  final BibleSearchService _bibleSearch = BibleSearchService();
  List<Video> _searchResults = [];
  List<BibleSearchHit> _rawBibleResults = [];
  List<BibleSearchHit> _bibleResults = [];
  String _bibleVersionId = BibleDownloadManager.defaultVersionId;
  _GlobalSearchFilter _filter = _GlobalSearchFilter.all;
  bool _isLoading = false;

  bool get _bibleEnabled => AppConfig.instanceId != 'centum_academy';

  @override
  void initState() {
    super.initState();
    if (_bibleEnabled) {
      _loadActiveVersion();
    }
  }

  Future<void> _loadActiveVersion() async {
    try {
      final settings = await BibleSettingsService().loadSettings();
      final saved = settings.lastVersion?.trim();
      if (mounted && saved != null && saved.isNotEmpty) {
        setState(() => _bibleVersionId = saved);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final videosFuture = _fetchVideos(trimmed);
      final bibleFuture = _bibleEnabled
          ? _bibleSearch.search(trimmed, versionId: _bibleVersionId, limit: 20)
          : Future<List<BibleSearchHit>>.value(const []);

      final results = await Future.wait([videosFuture, bibleFuture]);
      final rawBible = results[1] as List<BibleSearchHit>;
      final localizedBible = _bibleEnabled && rawBible.isNotEmpty
          ? await _bibleSearch.localizeHits(
              rawBible,
              versionId: _bibleVersionId,
            )
          : rawBible;
      if (!mounted) return;
      setState(() {
        _searchResults = results[0] as List<Video>;
        _rawBibleResults = rawBible;
        _bibleResults = localizedBible;
      });
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _switchBibleVersion(String newVersionId) async {
    final clean = newVersionId.trim();
    if (clean.isEmpty || clean == _bibleVersionId) return;
    setState(() => _bibleVersionId = clean);
    if (_rawBibleResults.isEmpty) return;
    final localized = await _bibleSearch.localizeHits(
      _rawBibleResults,
      versionId: clean,
    );
    if (mounted) {
      setState(() => _bibleResults = localized);
    }
  }

  Future<List<Video>> _fetchVideos(String query) async {
    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get(
          '/api/search',
          queryParameters: {'q': query, 'type': 'VIDEO'},
        );
      } catch (_) {
        response = await _apiClient.dio.get(
          '/videos',
          queryParameters: {'search': query, 'type': 'VIDEO'},
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        return list
            .whereType<Map<String, dynamic>>()
            .where((json) => !Short.isShort(json))
            .map((v) => Video.fromJson(v))
            .where((v) => v.type != 'SHORT')
            .toList();
      }
    } catch (e) {
      debugPrint('Video search error: $e');
    }
    return const [];
  }

  void _openBibleHit(BibleSearchHit hit) {
    final chapter = hit.chapter;
    final verse = hit.verse;
    final bookNum = hit.bookNumber;
    if (chapter == null || verse == null || bookNum == null) return;
    BiblePassageNavigator.instance.navigateTo(
      BibleReference(
        bookNumber: bookNum,
        chapter: chapter,
        verse: verse,
        versionId: _bibleVersionId,
      ),
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleVideos =
        _filter == _GlobalSearchFilter.bible ? const <Video>[] : _searchResults;
    final visibleBible = !_bibleEnabled || _filter == _GlobalSearchFilter.videos
        ? const <BibleSearchHit>[]
        : (_filter == _GlobalSearchFilter.all
            ? _bibleResults.take(3).toList()
            : _bibleResults);
    final hasAnyResults = visibleVideos.isNotEmpty || visibleBible.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${AppConfig.appName}...',
            border: InputBorder.none,
          ),
          onSubmitted: _performSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchResults = [];
                _rawBibleResults = [];
                _bibleResults = [];
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_bibleEnabled)
            MaxWidthBox(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  for (final f in _GlobalSearchFilter.values) ...[
                    ChoiceChip(
                      label: Text(
                        f == _GlobalSearchFilter.all
                            ? 'All'
                            : f == _GlobalSearchFilter.videos
                                ? 'Videos'
                                : 'Bible',
                      ),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !hasAnyResults
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search,
                                size: 64,
                                color: context.tokens.onSurfaceDisabled),
                            const SizedBox(height: 12),
                            Text(_bibleEnabled
                                ? 'Search videos, Bible verses, and lessons'
                                : 'Search ${AppConfig.appName} videos, lessons, and clips'),
                          ],
                        ),
                      )
                    : MaxWidthBox(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (visibleBible.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Bible',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    BibleVersionPill(
                                      activeVersionId: _bibleVersionId,
                                      onSelectVersion: _switchBibleVersion,
                                    ),
                                    if (_filter == _GlobalSearchFilter.all &&
                                        _bibleResults.length > 3) ...[
                                      const SizedBox(width: 4),
                                      TextButton(
                                        onPressed: () {
                                          final q =
                                              _searchController.text.trim();
                                          context.push(
                                            '/bible/search?q=${Uri.encodeComponent(q)}&version=${Uri.encodeComponent(_bibleVersionId)}',
                                          );
                                        },
                                        child: const Text('See all Bible'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              for (final hit in visibleBible)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                  child: Card(
                                    elevation: 0,
                                    color: context.tokens.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: context.tokens.surfaceBorder),
                                    ),
                                    child: ListTile(
                                      title: Text(
                                        hit.displayReference,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: context.accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      subtitle: Text(
                                        hit.text,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: hit.isPassage
                                          ? const Chip(
                                              label: Text('Passage'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            )
                                          : null,
                                      onTap: () => _openBibleHit(hit),
                                    ),
                                  ),
                                ),
                            ],
                            for (final video in visibleVideos)
                              SearchVideoCard(video: video),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
