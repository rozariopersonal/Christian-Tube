import 'package:flutter/foundation.dart';
import '../../books/services/scripture_ref_parser.dart';
import '../models/bible_book.dart';
import '../models/bible_search_hit.dart';
import '../services/bible_search_service.dart';

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
  final BibleSearchScope scope;
  final bool isSearching;
  final bool hasSearched;
  final ParsedScriptureRef? directRef;
  final List<BibleSearchHit> allResults;
  final List<BibleSearchHit> filteredResults;

  const BibleSearchState({
    this.query = '',
    this.scope = BibleSearchScope.all,
    this.isSearching = false,
    this.hasSearched = false,
    this.directRef,
    this.allResults = const [],
    this.filteredResults = const [],
  });

  BibleSearchState copyWith({
    String? query,
    BibleSearchScope? scope,
    bool? isSearching,
    bool? hasSearched,
    ParsedScriptureRef? directRef,
    bool clearDirectRef = false,
    List<BibleSearchHit>? allResults,
    List<BibleSearchHit>? filteredResults,
  }) {
    return BibleSearchState(
      query: query ?? this.query,
      scope: scope ?? this.scope,
      isSearching: isSearching ?? this.isSearching,
      hasSearched: hasSearched ?? this.hasSearched,
      directRef: clearDirectRef ? null : (directRef ?? this.directRef),
      allResults: allResults ?? this.allResults,
      filteredResults: filteredResults ?? this.filteredResults,
    );
  }
}

/// Manages Bible search query state, scope filtering, and direct reference
/// parsing outside the widget tree.
class BibleSearchController extends ChangeNotifier {
  final BibleSearchService _service;
  final String? versionId;
  final String? currentBook;
  late final int? _currentBookNumber;

  BibleSearchState _state = const BibleSearchState();
  BibleSearchState get state => _state;

  int _searchEpoch = 0;

  BibleSearchController({
    BibleSearchService? service,
    this.versionId,
    this.currentBook,
  }) : _service = service ?? BibleSearchService() {
    if (currentBook != null && currentBook!.isNotEmpty) {
      final idx = bibleBooks.keys.toList().indexOf(currentBook!);
      _currentBookNumber = idx >= 0 ? idx + 1 : null;
    } else {
      _currentBookNumber = null;
    }
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

  void clear() {
    _searchEpoch++;
    _state = BibleSearchState(scope: _state.scope);
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
    _state = _state.copyWith(
      query: trimmed,
      isSearching: true,
      hasSearched: true,
      directRef: direct,
      clearDirectRef: direct == null,
      allResults: const [],
      filteredResults: const [],
    );
    notifyListeners();

    final hits = await _service.search(
      trimmed,
      versionId: versionId,
      limit: 50,
    );
    if (epoch != _searchEpoch) return;

    _state = _state.copyWith(
      isSearching: false,
      allResults: hits,
      filteredResults: _applyScope(hits, _state.scope),
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
