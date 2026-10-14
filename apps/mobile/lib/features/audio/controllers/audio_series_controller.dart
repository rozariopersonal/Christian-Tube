import 'package:flutter/foundation.dart';

import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_download_service.dart';
import '../services/audio_storage_service.dart';

/// Immutable snapshot of the series detail screen state.
@immutable
class AudioSeriesViewState {
  final AudioSeries? series;
  final Map<String, int> savedPositions;
  final bool isLoading;
  final String searchQuery;

  const AudioSeriesViewState({
    this.series,
    this.savedPositions = const {},
    this.isLoading = true,
    this.searchQuery = '',
  });

  bool get isSearching => searchQuery.trim().isNotEmpty;

  /// Tracks matching the active in-channel search query. Falls back to the
  /// full list when the query is blank.
  List<AudioTrack> get filteredTracks {
    final tracks = series?.tracks ?? const <AudioTrack>[];
    final clean = searchQuery.trim().toLowerCase();
    if (clean.isEmpty) return tracks;
    return tracks.where((t) {
      return t.title.toLowerCase().contains(clean) ||
          t.speaker.toLowerCase().contains(clean) ||
          (t.youtubeVideoId ?? '').toLowerCase().contains(clean);
    }).toList();
  }

  AudioSeriesViewState copyWith({
    AudioSeries? series,
    bool clearSeries = false,
    Map<String, int>? savedPositions,
    bool? isLoading,
    String? searchQuery,
  }) {
    return AudioSeriesViewState(
      series: clearSeries ? null : (series ?? this.series),
      savedPositions: savedPositions ?? this.savedPositions,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Owns the series detail lifecycle: loading the full tracklist, restoring per
/// track playback positions, and reflecting any previously downloaded tracks.
/// The screen is a thin assembler that only listens to [state].
class AudioSeriesController extends ChangeNotifier {
  final String seriesId;
  final AudioCatalogService _catalogService;
  final AudioStorageService _storageService;

  AudioSeriesViewState _state;
  AudioSeriesViewState get state => _state;

  bool _disposed = false;

  AudioSeriesController({
    required this.seriesId,
    AudioSeries? initialSeries,
    AudioCatalogService? catalogService,
    AudioStorageService? storageService,
  })  : _catalogService = catalogService ?? AudioCatalogService(),
        _storageService = storageService ?? AudioStorageService(),
        _state = AudioSeriesViewState(series: initialSeries) {
    _load();
  }

  Future<void> _load() async {
    final series = await _catalogService.getSeries(seriesId);
    final positions = <String, int>{};
    if (series != null) {
      for (final track in series.tracks) {
        final pos = await _storageService.getPosition(track.id);
        if (pos > 0) {
          positions[track.id] = pos;
        }
      }
      // Reflect any previously downloaded tracks.
      AudioDownloadService.instance.syncFromDisk(series.tracks);
    }
    if (_disposed) return;
    _state = _state.copyWith(
      series: series ?? _state.series,
      savedPositions: positions,
      isLoading: false,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Updates the in-channel search query (filters the track list by
  /// title/speaker).
  void setSearchQuery(String query) {
    if (_state.searchQuery == query) return;
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
  }

  void clearSearch() => setSearchQuery('');
}