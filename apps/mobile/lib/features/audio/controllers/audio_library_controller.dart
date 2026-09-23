import 'package:flutter/foundation.dart';

import '../../../core/api/release_revision.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_meta.dart';
import '../../channels/channel_service.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_storage_service.dart';
import '../services/audio_subscription_filter.dart';
import '../services/audio_sync_manager.dart';
import 'audio_player_controller.dart';

enum AudioFormat { archive, songs, youtube }

enum AudioViewMode {
  featured,
  byCategory,
  bySpeaker,
  alphabetical,
}

/// Sort options for the YouTube channel grid in the Audio tab.
enum AudioChannelSort {
  /// Channels with the most tracks first.
  mostTracks,

  /// Alphabetical by channel name (A–Z).
  name,

  /// Channels with the most recently published track first.
  newest,
}

/// Immutable snapshot of the Audio Library browse state.
///
/// Follows the repository standard: views read this single derived value
/// object and never reach into services directly.
@immutable
class AudioLibraryViewState {
  final bool isLoading;
  final List<AudioSeries> seriesList;

  final AudioTrack? lastPlayedTrack;
  final int lastPlayedSeconds;

  final AudioFormat selectedFormat;
  final String selectedCategory;
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> languageTrackCounts;

  final String searchQuery;
  final AudioViewMode viewMode;
  final AudioChannelSort channelSort;
  final List<AudioSeries>? asyncSearchResults;

  /// Names of the channels the user is subscribed to. On the YouTube tab this
  /// restricts the channel grid to subscribed channels; empty means the tab
  /// shows its "subscribe" call to action instead.
  final Set<String> subscribedChannelNames;

  const AudioLibraryViewState({
    this.isLoading = true,
    this.seriesList = const [],
    this.asyncSearchResults,
    this.lastPlayedTrack,
    this.lastPlayedSeconds = 0,
    this.selectedFormat = AudioFormat.archive,
    this.selectedCategory = 'All',
    this.selectedLanguages = const {'All'},
    this.availableLanguages = const ['All'],
    this.languageTrackCounts = const {},
    this.searchQuery = '',
    this.viewMode = AudioViewMode.featured,
    this.channelSort = AudioChannelSort.mostTracks,
    this.subscribedChannelNames = const {},
  });

  bool get isAllLanguagesSelected =>
      selectedLanguages.isEmpty ||
      selectedLanguages.any((l) => l.toLowerCase() == 'all');

  bool get isSearching => searchQuery.trim().isNotEmpty;

  bool get hasChannelSubscriptions => subscribedChannelNames.isNotEmpty;

  /// Whether the YouTube tab should render its "subscribe" call to action:
  /// there is nothing to show because the user has no channel subscriptions.
  bool get shouldShowSubscribedCta =>
      selectedFormat == AudioFormat.youtube &&
      !hasChannelSubscriptions &&
      filteredSeries.isEmpty;

  AudioLibraryViewState copyWith({
    bool? isLoading,
    List<AudioSeries>? seriesList,
    List<AudioSeries>? asyncSearchResults,
    bool clearAsyncSearchResults = false,
    AudioTrack? lastPlayedTrack,
    bool clearLastPlayed = false,
    int? lastPlayedSeconds,
    AudioFormat? selectedFormat,
    String? selectedCategory,
    Set<String>? selectedLanguages,
    List<String>? availableLanguages,
    Map<String, int>? languageTrackCounts,
    String? searchQuery,
    AudioViewMode? viewMode,
    AudioChannelSort? channelSort,
    Set<String>? subscribedChannelNames,
  }) {
    return AudioLibraryViewState(
      isLoading: isLoading ?? this.isLoading,
      seriesList: seriesList ?? this.seriesList,
      asyncSearchResults: clearAsyncSearchResults ? null : (asyncSearchResults ?? this.asyncSearchResults),
      lastPlayedTrack:
          clearLastPlayed ? null : (lastPlayedTrack ?? this.lastPlayedTrack),
      lastPlayedSeconds: lastPlayedSeconds ?? this.lastPlayedSeconds,
      selectedFormat: selectedFormat ?? this.selectedFormat,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedLanguages: selectedLanguages ?? this.selectedLanguages,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      languageTrackCounts: languageTrackCounts ?? this.languageTrackCounts,
      searchQuery: searchQuery ?? this.searchQuery,
      viewMode: viewMode ?? this.viewMode,
      channelSort: channelSort ?? this.channelSort,
      subscribedChannelNames: {...(subscribedChannelNames ?? this.subscribedChannelNames)},
    );
  }

  /// Active format/category/language predicate shared by the browse list and
  /// the deep async search results so both surfaces honor the same filters.
  bool _matchesActiveFilters(AudioSeries s) {
    final isSong = s.category.toLowerCase() == 'songs';
    final isYouTube = s.category.toLowerCase() == 'youtube';

    if (selectedFormat == AudioFormat.songs && !isSong) return false;
    if (selectedFormat == AudioFormat.youtube && !isYouTube) return false;
    if (selectedFormat == AudioFormat.archive && (isSong || isYouTube)) return false;

    if (selectedFormat == AudioFormat.youtube &&
        !isSubscribedAudioSeries(
          subscribedChannelNames: subscribedChannelNames,
          series: s,
        )) {
      return false;
    }

    final matchesCategory =
        selectedCategory == 'All' || s.category == selectedCategory;
    if (selectedFormat == AudioFormat.archive && !matchesCategory) return false;

    if (isAllLanguagesSelected) return true;

    final code = LanguageMeta.canonicalCode(s.language);
    return code.isNotEmpty &&
        selectedLanguages.any((l) => l.toLowerCase() == code);
  }

  /// Series matching the active category and language filters.
  List<AudioSeries> get filteredSeries {
    return seriesList.where(_matchesActiveFilters).toList();
  }

  /// The YouTube channel grid, ordered by the active [channelSort].
  List<AudioSeries> get channelSortedSeries {
    final list = filteredSeries;
    switch (channelSort) {
      case AudioChannelSort.name:
        final sorted = List<AudioSeries>.from(list)
          ..sort((a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return sorted;
      case AudioChannelSort.newest:
        final sorted = List<AudioSeries>.from(list)
          ..sort((a, b) {
            final at = a.latestPublishedAt?.millisecondsSinceEpoch ?? -1;
            final bt = b.latestPublishedAt?.millisecondsSinceEpoch ?? -1;
            final recency = bt.compareTo(at);
            if (recency != 0) return recency;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        return sorted;
      case AudioChannelSort.mostTracks:
        return List<AudioSeries>.from(list)
          ..sort((a, b) => b.trackCount.compareTo(a.trackCount));
    }
  }

  /// Instant search results matching the active query against titles,
  /// speakers, categories, and descriptions. Uses deep async results if available.
  List<AudioSeries> get searchResults {
    final clean = searchQuery.trim().toLowerCase();
    if (clean.isEmpty) return filteredSeries;

    if (asyncSearchResults != null) {
      return asyncSearchResults!.where(_matchesActiveFilters).toList();
    }

    return filteredSeries.where((s) {
      return s.title.toLowerCase().contains(clean) ||
          s.speaker.toLowerCase().contains(clean) ||
          s.category.toLowerCase().contains(clean) ||
          s.description.toLowerCase().contains(clean);
    }).toList();
  }

  /// Groups matching series by Category.
  Map<String, List<AudioSeries>> get seriesByCategory {
    final map = <String, List<AudioSeries>>{};
    for (final s in filteredSeries) {
      final cat = s.category.isNotEmpty ? s.category : 'Archive';
      map.putIfAbsent(cat, () => []).add(s);
    }
    return map;
  }

  /// Groups matching series by Speaker / Author.
  Map<String, List<AudioSeries>> get seriesBySpeaker {
    final map = <String, List<AudioSeries>>{};
    for (final s in filteredSeries) {
      final speaker = s.speaker.isNotEmpty ? s.speaker : 'Zac Poonen';
      map.putIfAbsent(speaker, () => []).add(s);
    }
    return map;
  }

  /// Groups matching series alphabetically by first letter (A-Z, #).
  Map<String, List<AudioSeries>> get seriesAlphabetical {
    final sorted = List<AudioSeries>.from(filteredSeries)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final map = <String, List<AudioSeries>>{};
    for (final s in sorted) {
      final firstChar = s.title.trim().isNotEmpty
          ? s.title.trim()[0].toUpperCase()
          : '#';
      final groupKey = RegExp(r'[A-Z]').hasMatch(firstChar) ? firstChar : '#';
      map.putIfAbsent(groupKey, () => []).add(s);
    }
    return map;
  }
}

/// Owns the Audio Library browse lifecycle: catalog loading, continue-listening
/// state, and category/language filtering. The screen is a thin assembler that
/// only listens to [state].
class AudioLibraryController extends ChangeNotifier {
  static const categories = [
    'All',
    'Bible Survey',
    'Foundations',
    'Discipleship',
    'Christian Living',
    'Daily Devotions',
    'Verse By Verse',
    'Family & Home',
    'The Church',
    'Conferences',
    'Archive',
    'YouTube',
  ];

  final AudioCatalogService _catalogService;
  final AudioStorageService _storageService;

  /// Shared source of truth for the language filter. The whole library (books,
  /// songs, articles, audio) filters by this one selection.
  final LibraryLanguagesController _langController;
  late final bool _ownsLangController;

  /// Source of the user's channel subscriptions, bridged by name to audio
  /// YouTube series.
  final ChannelService _channelService;

  AudioLibraryViewState _state = const AudioLibraryViewState();
  AudioLibraryViewState get state => _state;

  LibraryLanguagesController get languageController => _langController;

  bool _disposed = false;

  /// Guards the best-effort channel-name fetch so it runs at most once per
  /// controller lifetime.
  bool _channelNamesFetchAttempted = false;

  AudioLibraryController({
    AudioCatalogService? catalogService,
    AudioStorageService? storageService,
    LibraryLanguagesController? langController,
    ChannelService? channelService,
  })  : _catalogService = catalogService ?? AudioCatalogService(),
        _storageService = storageService ?? AudioStorageService(),
        _langController = langController ?? LibraryLanguagesController(),
        _ownsLangController = langController == null,
        _channelService = channelService ?? ChannelService() {
    _state = AudioLibraryViewState(
      subscribedChannelNames: _channelService.subscribedChannelNames,
    );
    _langController.addListener(_onLangChanged);
    _channelService.addListener(_onChannelSubscriptionsChanged);
    loadData();
    AudioPlayerController.instance.addListener(_onPlayerStateChanged);
  }

  /// Channel subscriptions are keyed by channel id, but audio YouTube series
  /// only carry the channel name. Fetch the channel list (best effort, once)
  /// when names are missing so the grid can bridge subscriptions to series.
  void _ensureSubscribedChannelNames() {
    if (_channelNamesFetchAttempted) return;
    final ids = _channelService.subscribedChannelIds;
    if (ids.isEmpty) return;
    if (_channelService.subscribedChannelNames.length >= ids.length) return;
    _channelNamesFetchAttempted = true;
    _channelService.fetchChannels().catchError((e) {
      debugPrint('Failed to load channel names for audio subscriptions: $e');
    });
  }

  void _onChannelSubscriptionsChanged() {
    if (_disposed) return;
    _ensureSubscribedChannelNames();
    final names = _channelService.subscribedChannelNames;
    if (setEquals(names, _state.subscribedChannelNames)) return;
    _state = _state.copyWith(subscribedChannelNames: names);
    notifyListeners();
  }

  void _onLangChanged() {
    if (_disposed) return;
    _state = _state.copyWith(
      selectedLanguages: _langController.state.selectedLanguages,
    );
    notifyListeners();
  }

  void _onPlayerStateChanged() {
    if (_disposed) return;
    final player = AudioPlayerController.instance.state;
    if (player.currentTrack != null) {
      if (_state.lastPlayedTrack?.id != player.currentTrack!.id ||
          (_state.lastPlayedSeconds - player.position.inSeconds).abs() > 2) {
        _state = _state.copyWith(
          lastPlayedTrack: player.currentTrack,
          lastPlayedSeconds: player.position.inSeconds,
        );
        notifyListeners();
      }
    }
  }

  Future<void> loadData({bool forceRefresh = false}) async {
    // Make sure channel names are available to bridge subscriptions to audio
    // series when the singleton had already loaded by the time we attached.
    _ensureSubscribedChannelNames();

    // Check cloud for playback updates across devices in background
    AudioPlayerController.instance.syncWithCloud();

    final syncManager = AudioSyncManager(_catalogService.localAdapter);

    if (forceRefresh) {
      // On explicit refresh: refresh the dataset revision FIRST so CDN URLs
      // pick up the new cache-busting query, clear in-memory caches, then
      // re-sync the local SQLite mirror and only THEN read the catalog. This
      // removes the stale-count race for both the CDN and SQLite paths.
      await ReleaseRevision.load();
      _catalogService.invalidateCaches();
      try {
        await syncManager.syncCatalog(fullRefresh: true);
      } catch (e) {
        debugPrint('Audio sync failed during force refresh: $e');
      }
    } else {
      // Background catalog sync from NestJS to Local SQLite (best effort).
      syncManager.syncCatalog().catchError((e) {
        debugPrint('Background sync failed: $e');
      });
    }

    final catalog = await _catalogService.getCatalog(forceRefresh: forceRefresh);
    final lastTrack = await _storageService.getLastTrack();
    int lastSec = 0;
    if (lastTrack != null) {
      lastSec = await _storageService.getPosition(lastTrack.id);
    }

    final counts = <String, int>{'All': 0};
    final Set<String> uniqueLangs = {};

    for (final s in catalog) {
      final lang = LanguageMeta.canonicalCode(s.language);
      if (lang.isEmpty || lang == 'all') continue;
      uniqueLangs.add(lang);
      counts['All'] = (counts['All'] ?? 0) + s.trackCount;
      counts[lang] = (counts[lang] ?? 0) + s.trackCount;
    }

    final sortedLangs = uniqueLangs.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    // Register this content type's languages with the shared controller.
    _langController.announceLanguages(uniqueLangs);

    if (_disposed) return;
    _state = _state.copyWith(
      isLoading: false,
      seriesList: catalog,
      lastPlayedTrack: lastTrack,
      lastPlayedSeconds: lastSec,
      languageTrackCounts: counts,
      availableLanguages: ['All', ...sortedLangs],
      selectedLanguages: _langController.state.selectedLanguages,
    );
    notifyListeners();
  }

  void selectCategory(String category) {
    _state = _state.copyWith(selectedCategory: category);
    notifyListeners();
  }

  void selectFormat(AudioFormat format) {
    if (_state.selectedFormat == format) return;
    _state = _state.copyWith(selectedFormat: format, selectedCategory: 'All');
    notifyListeners();
  }

  void selectLanguages(Set<String> newSelection) {
    _langController.selectLanguages(newSelection);
  }

  void setSearchQuery(String query) {
    if (_state.searchQuery == query) return;
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
    
    if (query.trim().isNotEmpty) {
      _performAsyncSearch(query.trim());
    }
  }
  
  Future<void> _performAsyncSearch(String query) async {
    try {
      final results = await _catalogService.search(query);
      if (_disposed || _state.searchQuery != query) return;
      _state = _state.copyWith(asyncSearchResults: results);
      notifyListeners();
    } catch (_) {
      // Fallback to in-memory filter if error
    }
  }

  void clearSearch() {
    if (_state.searchQuery.isEmpty) return;
    _state = _state.copyWith(searchQuery: '', clearAsyncSearchResults: true);
    notifyListeners();
  }

  void setViewMode(AudioViewMode mode) {
    if (_state.viewMode == mode) return;
    _state = _state.copyWith(viewMode: mode);
    notifyListeners();
  }

  void setChannelSort(AudioChannelSort sort) {
    if (_state.channelSort == sort) return;
    _state = _state.copyWith(channelSort: sort);
    notifyListeners();
  }

  void resetFilters() {
    _state = _state.copyWith(
      selectedFormat: AudioFormat.archive,
      selectedCategory: 'All',
      searchQuery: '',
      viewMode: AudioViewMode.featured,
    );
    notifyListeners();
    _langController.reset();
  }

  @override
  void dispose() {
    _disposed = true;
    _langController.removeListener(_onLangChanged);
    _channelService.removeListener(_onChannelSubscriptionsChanged);
    if (_ownsLangController) _langController.dispose();
    AudioPlayerController.instance.removeListener(_onPlayerStateChanged);
    super.dispose();
  }
}