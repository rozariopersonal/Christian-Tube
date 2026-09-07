import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../books/models/book_language_meta.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_storage_service.dart';
import 'audio_player_controller.dart';

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

  final String selectedCategory;
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> languageTrackCounts;

  const AudioLibraryViewState({
    this.isLoading = true,
    this.seriesList = const [],
    this.lastPlayedTrack,
    this.lastPlayedSeconds = 0,
    this.selectedCategory = 'All',
    this.selectedLanguages = const {'All'},
    this.availableLanguages = const ['All'],
    this.languageTrackCounts = const {},
  });

  bool get isAllLanguagesSelected =>
      selectedLanguages.isEmpty ||
      selectedLanguages.any((l) => l.toLowerCase() == 'all');

  AudioLibraryViewState copyWith({
    bool? isLoading,
    List<AudioSeries>? seriesList,
    AudioTrack? lastPlayedTrack,
    bool clearLastPlayed = false,
    int? lastPlayedSeconds,
    String? selectedCategory,
    Set<String>? selectedLanguages,
    List<String>? availableLanguages,
    Map<String, int>? languageTrackCounts,
  }) {
    return AudioLibraryViewState(
      isLoading: isLoading ?? this.isLoading,
      seriesList: seriesList ?? this.seriesList,
      lastPlayedTrack:
          clearLastPlayed ? null : (lastPlayedTrack ?? this.lastPlayedTrack),
      lastPlayedSeconds: lastPlayedSeconds ?? this.lastPlayedSeconds,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedLanguages: selectedLanguages ?? this.selectedLanguages,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      languageTrackCounts: languageTrackCounts ?? this.languageTrackCounts,
    );
  }

  /// Series matching the active category and language filters.
  List<AudioSeries> get filteredSeries {
    final isAll = isAllLanguagesSelected;

    return seriesList.where((s) {
      final matchesCategory =
          selectedCategory == 'All' || s.category == selectedCategory;
      if (!matchesCategory) return false;

      if (isAll) return true;

      final sLangLower = s.language.toLowerCase();
      final sMeta = BookLanguageMeta.fromCode(s.language);

      return selectedLanguages.any((l) {
        final lLower = l.toLowerCase();
        final lMeta = BookLanguageMeta.fromCode(l);
        return lLower == sLangLower ||
            lMeta.englishName.toLowerCase() == sLangLower ||
            lLower == sMeta.code.toLowerCase() ||
            lMeta.code.toLowerCase() == sMeta.code.toLowerCase();
      });
    }).toList();
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

  static const _prefKeyLanguages = 'audio_library_languages';

  final AudioCatalogService _catalogService;
  final AudioStorageService _storageService;

  AudioLibraryViewState _state = const AudioLibraryViewState();
  AudioLibraryViewState get state => _state;

  bool _disposed = false;

  AudioLibraryController({
    AudioCatalogService? catalogService,
    AudioStorageService? storageService,
  })  : _catalogService = catalogService ?? AudioCatalogService(),
        _storageService = storageService ?? AudioStorageService() {
    loadData();
    AudioPlayerController.instance.addListener(_onPlayerStateChanged);
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
      final lang = s.language.trim();
      if (lang.isEmpty) continue;
      uniqueLangs.add(lang);
      counts['All'] = (counts['All'] ?? 0) + s.trackCount;
      counts[lang] = (counts[lang] ?? 0) + s.trackCount;
    }

    final sortedLangs = uniqueLangs.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefKeyLanguages);
    final initialSelection = (saved != null && saved.isNotEmpty)
        ? saved.toSet()
        : _state.selectedLanguages;

    if (_disposed) return;
    _state = _state.copyWith(
      isLoading: false,
      seriesList: catalog,
      lastPlayedTrack: lastTrack,
      lastPlayedSeconds: lastSec,
      languageTrackCounts: counts,
      availableLanguages: ['All', ...sortedLangs],
      selectedLanguages: initialSelection,
    );
    notifyListeners();
  }

  void selectCategory(String category) {
    _state = _state.copyWith(selectedCategory: category);
    notifyListeners();
  }

  void selectLanguages(Set<String> newSelection) {
    final valid = newSelection.isEmpty ? {'All'} : newSelection;
    _state = _state.copyWith(selectedLanguages: valid);
    notifyListeners();
    SharedPreferences.getInstance().then((p) {
      p.setStringList(_prefKeyLanguages, valid.toList());
    });
  }

  void resetFilters() {
    _state = _state.copyWith(
      selectedCategory: 'All',
      selectedLanguages: const {'All'},
    );
    notifyListeners();
    SharedPreferences.getInstance().then((p) {
      p.setStringList(_prefKeyLanguages, ['All']);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    AudioPlayerController.instance.removeListener(_onPlayerStateChanged);
    super.dispose();
  }
}