import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../shared/ui/bible_version_pill.dart';
import '../../shared/ui/search_video_card.dart';
import '../../core/config/app_config.dart';
import '../bible/models/bible_reference.dart';
import '../bible/models/bible_search_hit.dart';
import '../bible/services/bible_passage_navigator.dart';
import '../bible/services/bible_search_service.dart';
import '../bible/services/bible_settings_service.dart';
import '../engines/scripture/services/bible_download_manager.dart';

enum _GlobalSearchFilter { all, videos, shorts, bible }

enum _SearchSort { relevance, latest, popular }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const int _pageSize = 24;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiClient _apiClient = ApiClient();
  final BibleSearchService _bibleSearch = BibleSearchService();

  List<Video> _searchResults = [];
  List<BibleSearchHit> _rawBibleResults = [];
  List<BibleSearchHit> _bibleResults = [];
  String _bibleVersionId = BibleDownloadManager.defaultVersionId;
  _GlobalSearchFilter _filter = _GlobalSearchFilter.all;
  _SearchSort _sort = _SearchSort.relevance;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasSearched = false;
  bool _hasMore = false;
  String _submittedQuery = '';
  String? _errorMessage;
  int _offset = 0;
  int _searchSeq = 0;
  CancelToken? _activeCancelToken;

  bool get _bibleEnabled => AppConfig.instanceId != 'centum_academy';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
    _activeCancelToken?.cancel('disposed');
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    if (_filter == _GlobalSearchFilter.bible) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMoreVideos();
    }
  }

  String _apiTypeForFilter() {
    switch (_filter) {
      case _GlobalSearchFilter.videos:
        return 'VIDEO';
      case _GlobalSearchFilter.shorts:
        return 'SHORT';
      case _GlobalSearchFilter.all:
      case _GlobalSearchFilter.bible:
        return 'ALL';
    }
  }

  String _apiSortValue() {
    switch (_sort) {
      case _SearchSort.latest:
        return 'latest';
      case _SearchSort.popular:
        return 'popular';
      case _SearchSort.relevance:
        return 'relevance';
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _activeCancelToken?.cancel('superseded');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final seq = ++_searchSeq;

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasSearched = true;
      _submittedQuery = trimmed;
      _errorMessage = null;
      _offset = 0;
      _hasMore = false;
    });

    try {
      final shouldFetchVideos = _filter != _GlobalSearchFilter.bible;
      final shouldFetchBible =
          _bibleEnabled &&
          (_filter == _GlobalSearchFilter.all || _filter == _GlobalSearchFilter.bible);

      final videosFuture = shouldFetchVideos
          ? _fetchVideos(trimmed, offset: 0, cancelToken: cancelToken)
          : Future<List<Video>>.value(const []);
      final bibleFuture = shouldFetchBible
          ? _bibleSearch.search(trimmed, versionId: _bibleVersionId, limit: 20)
          : Future<List<BibleSearchHit>>.value(const []);

      final results = await Future.wait([videosFuture, bibleFuture]);
      if (!mounted || seq != _searchSeq) return;

      final videos = results[0] as List<Video>;
      final rawBible = results[1] as List<BibleSearchHit>;
      final localizedBible = shouldFetchBible && rawBible.isNotEmpty
          ? await _bibleSearch.localizeHits(
              rawBible,
              versionId: _bibleVersionId,
            )
          : rawBible;
      if (!mounted || seq != _searchSeq) return;

      setState(() {
        _searchResults = videos;
        _rawBibleResults = rawBible;
        _bibleResults = localizedBible;
        _offset = videos.length;
        _hasMore = shouldFetchVideos && videos.length >= _pageSize;
        _errorMessage = null;
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _errorMessage = 'Could not complete search. Check your connection and try again.';
      });
    } catch (e) {
      debugPrint('Search error: $e');
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _errorMessage = 'Something went wrong while searching. Please try again.';
      });
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    final trimmed = _submittedQuery;
    if (trimmed.isEmpty || _isLoadingMore || !_hasMore) return;

    final seq = _searchSeq;
    final cancelToken = _activeCancelToken ?? CancelToken();
    setState(() => _isLoadingMore = true);

    try {
      final batch = await _fetchVideos(
        trimmed,
        offset: _offset,
        cancelToken: cancelToken,
      );
      if (!mounted || seq != _searchSeq) return;
      final existingIds = _searchResults.map((v) => v.id).toSet();
      final next = batch.where((v) => !existingIds.contains(v.id)).toList();
      setState(() {
        _searchResults = [..._searchResults, ...next];
        _offset += batch.length;
        _hasMore = batch.length >= _pageSize;
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (mounted && seq == _searchSeq) {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      debugPrint('Load more search error: $e');
      if (mounted && seq == _searchSeq) {
        setState(() => _hasMore = false);
      }
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() => _isLoadingMore = false);
      }
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

  Future<List<Video>> _fetchVideos(
    String query, {
    required int offset,
    required CancelToken cancelToken,
  }) async {
    final response = await _apiClient.dio.get(
      '/api/search',
      queryParameters: {
        'q': query,
        'type': _apiTypeForFilter(),
        'sort': _apiSortValue(),
        'limit': _pageSize,
        'offset': offset,
      },
      cancelToken: cancelToken,
    );

    if (response.statusCode == 200 && response.data != null) {
      final dynamic raw = response.data;
      final List<dynamic> list =
          raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
      return list
          .whereType<Map<String, dynamic>>()
          .map((v) => Video.fromJson(v))
          .toList();
    }
    return const [];
  }

  void _selectFilter(_GlobalSearchFilter next) {
    if (_filter == next) return;
    setState(() => _filter = next);
    if (_searchController.text.trim().isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _selectSort(_SearchSort next) {
    if (_sort == next) return;
    setState(() => _sort = next);
    if (_searchController.text.trim().isNotEmpty &&
        _filter != _GlobalSearchFilter.bible) {
      _performSearch(_searchController.text);
    }
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
    final visibleBible = !_bibleEnabled ||
            _filter == _GlobalSearchFilter.videos ||
            _filter == _GlobalSearchFilter.shorts
        ? const <BibleSearchHit>[]
        : (_filter == _GlobalSearchFilter.all
            ? _bibleResults.take(3).toList()
            : _bibleResults);
    final hasAnyResults = visibleVideos.isNotEmpty || visibleBible.isNotEmpty;

    final availableFilters = _bibleEnabled
        ? _GlobalSearchFilter.values
        : const [
            _GlobalSearchFilter.all,
            _GlobalSearchFilter.videos,
            _GlobalSearchFilter.shorts,
          ];

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
              _activeCancelToken?.cancel('cleared');
              _searchSeq++;
              _searchController.clear();
              setState(() {
                _searchResults = [];
                _rawBibleResults = [];
                _bibleResults = [];
                _hasSearched = false;
                _submittedQuery = '';
                _hasMore = false;
                _errorMessage = null;
                _isLoading = false;
                _isLoadingMore = false;
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
          MaxWidthBox(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in availableFilters) ...[
                    ChoiceChip(
                      label: Text(
                        f == _GlobalSearchFilter.all
                            ? 'All'
                            : f == _GlobalSearchFilter.videos
                                ? 'Videos'
                                : f == _GlobalSearchFilter.shorts
                                    ? 'Shorts'
                                    : 'Bible',
                      ),
                      selected: _filter == f,
                      onSelected: (_) => _selectFilter(f),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_filter != _GlobalSearchFilter.bible)
                    PopupMenuButton<_SearchSort>(
                      initialValue: _sort,
                      onSelected: _selectSort,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _SearchSort.relevance,
                          child: Text('Relevance'),
                        ),
                        PopupMenuItem(
                          value: _SearchSort.latest,
                          child: Text('Newest'),
                        ),
                        PopupMenuItem(
                          value: _SearchSort.popular,
                          child: Text('Most viewed'),
                        ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.sort, size: 16),
                        label: Text(
                          _sort == _SearchSort.relevance
                              ? 'Relevance'
                              : _sort == _SearchSort.latest
                                  ? 'Newest'
                                  : 'Popular',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off_rounded,
                                  size: 48,
                                  color: context.tokens.onSurfaceDisabled),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: () =>
                                    _performSearch(_searchController.text),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !hasAnyResults
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _hasSearched
                                        ? Icons.search_off_rounded
                                        : Icons.search,
                                    size: 64,
                                    color: context.tokens.onSurfaceDisabled,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _hasSearched
                                        ? 'No results for "$_submittedQuery"'
                                        : (_bibleEnabled
                                            ? 'Search videos, shorts, and Bible verses'
                                            : 'Search ${AppConfig.appName} videos, lessons, and clips'),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : MaxWidthBox(
                            child: ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                if (visibleBible.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 4),
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Bible',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700),
                                        ),
                                        BibleVersionPill(
                                          activeVersionId: _bibleVersionId,
                                          onSelectVersion: _switchBibleVersion,
                                        ),
                                        if (_filter ==
                                                _GlobalSearchFilter.all &&
                                            _bibleResults.length > 3)
                                          TextButton(
                                            onPressed: () {
                                              context.push(
                                                '/bible/search?q=${Uri.encodeComponent(_submittedQuery)}&version=${Uri.encodeComponent(_bibleVersionId)}',
                                              );
                                            },
                                            child: const Text('See all Bible'),
                                          ),
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
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          side: BorderSide(
                                              color:
                                                  context.tokens.surfaceBorder),
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
                                if (_isLoadingMore)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
