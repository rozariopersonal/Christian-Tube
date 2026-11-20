import 'package:flutter/foundation.dart';
import '../../books/services/scripture_ref_parser.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../models/bible_book.dart';
import '../models/bible_search_hit.dart';
import '../services/bible_search_service.dart';
import '../services/bible_settings_service.dart';

enum BibleSearchScope {
  all('Entire Bible'),
  ot('Old Testament'),
  nt('New Testament'),
  book('Current Book');

  final String label;
  const BibleSearchScope(this.label);
}

@immutable
class BibleSearchState {
  final String query;
  final String versionId;
  final BibleSearchScope scope;
  final bool isSearching;
  final bool isTranslating;
  final bool hasSearched;
  final ParsedScriptureRef? directRef;
  final List<BibleSearchHit> allResults;
  final List<BibleSearchHit> filteredResults;

  const BibleSearchState({
    this.query = '',
    this.versionId = BibleDownloadManager.defaultVersionId,
    this.scope = BibleSearchScope.all,
    this.isSearching = false,
    this.isTranslating = false,
    this.hasSearched = false,
    this.directRef,
    this.allResults = const [],
    this.filteredResults = const [],
  });

  BibleSearchState copyWith({
    String? query,
    String? versionId,
    BibleSearchScope? scope,
    bool? isSearching,
    bool? isTranslating,
    bool? hasSearched,
    ParsedScriptureRef? directRef,
    bool clearDirectRef = false,
    List<BibleSearchHit>? allResults,
    List<BibleSearchHit>? filteredResults,
  }) {
    return BibleSearchState(
      query: query ?? this.query,
      versionId: versionId ?? this.versionId,
      scope: scope ?? this.scope,
      isSearching: isSearching ?? this.isSearching,
      isTranslating: isTranslating ?? this.isTranslating,
      hasSearched: hasSearched ?? this.hasSearched,
      directRef: clearDirectRef ? null : (directRef ?? this.directRef),
      allResults: allResults ?? this.allResults,
      filteredResults: filteredResults ?? this.filteredResults,
    );
  }
}

/// Manages Bible search query state, active Bible version translation of
/// results, scope filtering, and direct reference parsing.
class BibleSearchController extends ChangeNotifier {
  final BibleSearchService _service;
  final String? currentBook;
  late final int? _currentBookNumber;
  List<BibleSearchHit> _rawResults = const [];

  late BibleSearchState _state;
  BibleSearchState get state => _state;

  int _searchEpoch = 0;

  BibleSearchController({
    BibleSearchService? service,
    String? versionId,
    this.currentBook,
  }) : _service = service ?? BibleSearchService() {
    final initialVersion = (versionId != null && versionId.trim().isNotEmpty)
        ? versionId.trim()
        : BibleDownloadManager.defaultVersionId;
    _state = BibleSearchState(versionId: initialVersion);

    if (currentBook != null && currentBook!.isNotEmpty) {
      final idx = bibleBooks.keys.toList().indexOf(currentBook!);
      _currentBookNumber = idx >= 0 ? idx + 1 : null;
    } else {
      _currentBookNumber = null;
    }

    if (versionId == null || versionId.trim().isEmpty) {
      _resolveDefaultActiveVersion();
    }
  }

  Future<void> _resolveDefaultActiveVersion() async {
    try {
      final settings = await BibleSettingsService().loadSettings();
      final saved = settings.lastVersion?.trim();
      if (saved != null && saved.isNotEmpty && saved != _state.versionId) {
        _state = _state.copyWith(versionId: saved);
        notifyListeners();
      }
    } catch (_) {}
  }

  List<BibleSearchScope> get availableScopes => _currentBookNumber != null
      ? BibleSearchScope.values
      : const [BibleSearchScope.all, BibleSearchScope.ot, BibleSearchScope.nt];

  void setScope(BibleSearchScope scope) {
    if (_state.scope == scope) return;
    _state = _state.copyWith(
      scope: scope,
      filteredResults: _applyScope(_state.allResults, scope),
    );
    notifyListeners();
  }

  /// Switches the display Bible version and re-hydrates cached search results
  /// into that translation without re-querying the backend search endpoint.
  Future<void> setVersion(String newVersionId) async {
    final clean = newVersionId.trim();
    if (clean.isEmpty || clean == _state.versionId) return;

    _state = _state.copyWith(
      versionId: clean,
      isTranslating: _rawResults.isNotEmpty,
    );
    notifyListeners();

    if (_rawResults.isEmpty) return;

    final epoch = _searchEpoch;
    final localized = await _service.localizeHits(
      _rawResults,
      versionId: clean,
    );
    if (epoch != _searchEpoch) return;

    _state = _state.copyWith(
      isTranslating: false,
      allResults: localized,
      filteredResults: _applyScope(localized, _state.scope),
    );
    notifyListeners();
  }

  void clear() {
    _searchEpoch++;
    _rawResults = const [];
    _state = BibleSearchState(
      versionId: _state.versionId,
      scope: _state.scope,
    );
    notifyListeners();
  }

  Future<void> search(String rawQuery) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }

    final epoch = ++_searchEpoch;
    final direct = _service.parseDirectReference(trimmed);
    _rawResults = const [];
    _state = _state.copyWith(
      query: trimmed,
      isSearching: true,
      isTranslating: false,
      hasSearched: true,
      directRef: direct,
      clearDirectRef: direct == null,
      allResults: const [],
      filteredResults: const [],
    );
    notifyListeners();

    final rawHits = await _service.search(
      trimmed,
      versionId: _state.versionId,
      limit: 50,
    );
    if (epoch != _searchEpoch) return;

    _rawResults = rawHits;
    final localized = await _service.localizeHits(
      rawHits,
      versionId: _state.versionId,
    );
    if (epoch != _searchEpoch) return;

    _state = _state.copyWith(
      isSearching: false,
      allResults: localized,
      filteredResults: _applyScope(localized, _state.scope),
    );
    notifyListeners();
  }

  List<BibleSearchHit> _applyScope(
    List<BibleSearchHit> hits,
    BibleSearchScope scope,
  ) {
    if (scope == BibleSearchScope.all) return hits;
    return hits.where((hit) {
      final bn = hit.bookNumber;
      if (bn == null) return false;
      switch (scope) {
        case BibleSearchScope.ot:
          return bn <= 39;
        case BibleSearchScope.nt:
          return bn >= 40;
        case BibleSearchScope.book:
          return _currentBookNumber != null && bn == _currentBookNumber;
        case BibleSearchScope.all:
          return true;
      }
    }).toList();
  }
}
