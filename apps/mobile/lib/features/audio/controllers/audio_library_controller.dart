import 'package:flutter/foundation.dart';

import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_meta.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_storage_service.dart';
import 'audio_player_controller.dart';

enum AudioFormat { sermons, songs }

enum AudioViewMode {
  featured,
  byCategory,
  bySpeaker,
  alphabetical,
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

  const AudioLibraryViewState({
    this.isLoading = true,
    this.seriesList = const [],
    this.lastPlayedTrack,
    this.lastPlayedSeconds = 0,
    this.selectedFormat = AudioFormat.sermons,
    this.selectedCategory = 'All',
    this.selectedLanguages = const {'All'},
    this.availableLanguages = const ['All'],
    this.languageTrackCounts = const {},
    this.searchQuery = '',
    this.viewMode = AudioViewMode.featured,
  });

  bool get isAllLanguagesSelected =>
      selectedLanguages.isEmpty ||
      selectedLanguages.any((l) => l.toLowerCase() == 'all');

  bool get isSearching => searchQuery.trim().isNotEmpty;

  AudioLibraryViewState copyWith({
    bool? isLoading,
    List<AudioSeries>? seriesList,
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
  }) {
    return AudioLibraryViewState(
      isLoading: isLoading ?? this.isLoading,
      seriesList: seriesList ?? this.seriesList,
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
    );
  }

  /// Series matching the active category and language filters. Language values
  /// are canonicalized (names like `English` become `en`) so they line up with
  /// the shared controller's code-based selection.
  List<AudioSeries> get filteredSeries {
    final isAll = isAllLanguagesSelected;

    return seriesList.where((s) {
      final isSong = s.category.toLowerCase() == 'songs';
      if (selectedFormat == AudioFormat.songs && !isSong) return false;
      if (selectedFormat == AudioFormat.sermons && isSong) return false;

      final matchesCategory =
          selectedCategory == 'All' || s.category == selectedCategory;
      if (selectedFormat == AudioFormat.sermons && !matchesCategory) return false;

      if (isAll) return true;

      final code = LanguageMeta.canonicalCode(s.language);
      return code.isNotEmpty &&
          selectedLanguages.any((l) => l.toLowerCase() == code);
    }).toList();
  }

  /// Instant search results matching the active query against titles,
  /// speakers, categories, and descriptions.
  List<AudioSeries> get searchResults {
    final clean = searchQuery.trim().toLowerCase();
    if (clean.isEmpty) return filteredSeries;

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
      final cat = s.category.isNotEmpty ? s.category : 'General Sermons';
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
    'General Sermons',
  ];

  final AudioCatalogService _catalogService;
  final AudioStorageService _storageService;

  /// Shared source of truth for the language filter. The whole library (books,
  /// songs, articles, audio) filters by this one selection.
  final LibraryLanguagesController _langController;
  late final bool _ownsLangController;

  AudioLibraryViewState _state = const AudioLibraryViewState();
  AudioLibraryViewState get state => _state;

  LibraryLanguagesController get languageController => _langController;

  bool _disposed = false;

  AudioLibraryController({
    AudioCatalogService? catalogService,
    AudioStorageService? storageService,
    LibraryLanguagesController? langController,
  })  : _catalogService = catalogService ?? AudioCatalogService(),
        _storageService = storageService ?? AudioStorageService(),
        _langController = langController ?? LibraryLanguagesController(),
        _ownsLangController = langController == null {
    _langController.addListener(_onLangChanged);
    loadData();
    AudioPlayerController.instance.addListener(_onPlayerStateChanged);
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
    // Check cloud for playback updates across devices in background
    AudioPlayerController.instance.syncWithCloud();

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
  }

  void clearSearch() {
    if (_state.searchQuery.isEmpty) return;
    _state = _state.copyWith(searchQuery: '');
    notifyListeners();
  }

  void setViewMode(AudioViewMode mode) {
    if (_state.viewMode == mode) return;
    _state = _state.copyWith(viewMode: mode);
    notifyListeners();
  }

  void resetFilters() {
    _state = _state.copyWith(
      selectedFormat: AudioFormat.sermons,
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
    if (_ownsLangController) _langController.dispose();
    AudioPlayerController.instance.removeListener(_onPlayerStateChanged);
    super.dispose();
  }
}