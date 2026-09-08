import 'package:flutter/foundation.dart';

import '../../../shared/services/library_languages_controller.dart';
import '../models/song.dart';
import '../models/song_collection.dart';
import '../services/songs_catalog_service.dart';

/// How the songs browser groups its listing.
enum SongGroupMode { albums, authors, collections }

/// Immutable snapshot of the songs browse state.
@immutable
class SongsViewState {
  final bool isLoading;
  final List<Song> songs;
  final SongGroupMode groupMode;

  const SongsViewState({
    this.isLoading = true,
    this.songs = const [],
    this.groupMode = SongGroupMode.albums,
  });

  SongsViewState copyWith({
    bool? isLoading,
    List<Song>? songs,
    SongGroupMode? groupMode,
  }) {
    return SongsViewState(
      isLoading: isLoading ?? this.isLoading,
      songs: songs ?? this.songs,
      groupMode: groupMode ?? this.groupMode,
    );
  }
}

/// Owns the Songs browse lifecycle: loading the catalog, filtering by the
/// global language, and grouping into albums / authors / collections.
///
/// Language filtering reads the shared [LibraryLanguagesController], making
/// songs part of the app-wide single language source of truth.
class SongsLibraryController extends ChangeNotifier {
  final SongsCatalogService _service;
  final LibraryLanguagesController _langController;
  late final bool _ownsLangController;

  SongsViewState _state = const SongsViewState();
  SongsViewState get state => _state;

  /// The shared language controller backing the browse filter. When no
  /// controller is supplied (route-pushed), one is created and owned here.
  LibraryLanguagesController get languageController => _langController;

  SongsLibraryController({
    SongsCatalogService? service,
    LibraryLanguagesController? langController,
  })  : _service = service ?? SongsCatalogService(),
        _langController = langController ?? LibraryLanguagesController(),
        _ownsLangController = langController == null {
    _langController.addListener(_onLanguageChanged);
    load();
  }

  void _onLanguageChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _langController.removeListener(_onLanguageChanged);
    if (_ownsLangController) _langController.dispose();
    super.dispose();
  }

  Future<void> load({bool forceRefresh = false}) async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();
    try {
      final songs = await _service.getSongs(forceRefresh: forceRefresh);
      if (!forceRefresh && songs.isEmpty && _state.songs.isNotEmpty) {
        // Transient failure (e.g. network hiccup) — keep the last-known list
        // instead of wiping the shelf with an empty result.
        _state = _state.copyWith(isLoading: false);
        notifyListeners();
        return;
      }
      _state = _state.copyWith(isLoading: false, songs: songs);
      _announceLanguages(songs);
    } catch (e) {
      debugPrint('Songs catalog load failed: $e');
      _state = _state.copyWith(isLoading: false);
    }
    notifyListeners();
  }

  void setGroupMode(SongGroupMode mode) {
    if (_state.groupMode == mode) return;
    _state = _state.copyWith(groupMode: mode);
    notifyListeners();
  }

  void _announceLanguages(List<Song> songs) {
    final codes = <String>{};
    for (final s in songs) {
      if (s.language.isNotEmpty) codes.add(s.language);
    }
    _langController.announceLanguages(codes);
  }

  /// Per-language song counts across the whole loaded catalog (plus `All`),
  /// used to render truthful item counts in the shared dropdown.
  Map<String, int> get languageCounts {
    final counts = <String, int>{'All': 0};
    for (final s in _state.songs) {
      final code = s.language.toLowerCase();
      if (code.isEmpty) continue;
      counts['All'] = (counts['All'] ?? 0) + 1;
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  }

  /// Songs filtered by the global language selection.
  List<Song> get filteredSongs {
    final langState = _langController.state;
    if (langState.isAllLanguages) return _state.songs;
    return _state.songs.where((s) => langState.includes(s.language)).toList();
  }

  List<SongCollection> get groupedSongs {
    final songs = filteredSongs;
    final Map<String, List<Song>> groups = {};
    final Map<String, String?> subtitles = {};

    switch (_state.groupMode) {
      case SongGroupMode.albums:
        for (final s in songs) {
          final key = (s.album?.isNotEmpty ?? false) ? s.album! : 'Uncategorized';
          if (!groups.containsKey(key)) subtitles[key] = s.author;
          groups.putIfAbsent(key, () => []).add(s);
        }
      case SongGroupMode.authors:
        for (final s in songs) {
          final key = (s.author?.isNotEmpty ?? false) ? s.author! : 'Unknown Author';
          groups.putIfAbsent(key, () => []).add(s);
        }
      case SongGroupMode.collections:
        for (final s in songs) {
          final key =
              (s.collection?.isNotEmpty ?? false) ? s.collection! : 'General';
          if (!groups.containsKey(key)) subtitles[key] = s.language;
          groups.putIfAbsent(key, () => []).add(s);
        }
    }

    final sortedKeys = groups.keys.toList()..sort();
    return sortedKeys
        .map((k) => SongCollection(
              label: k,
              subtitle: subtitles[k],
              songs: groups[k]!,
            ))
        .toList();
  }
}
