import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/language_meta.dart';

/// Immutable snapshot of the global library language filter.
@immutable
class LibraryLanguagesState {
  final Set<String> selectedLanguages;

  /// Every language code available across the whole library, plus 'All'.
  final List<String> availableLanguages;

  const LibraryLanguagesState({
    this.selectedLanguages = const {'All'},
    this.availableLanguages = const ['All'],
  });

  bool get isAllLanguages => selectedLanguages.isEmpty ||
      selectedLanguages.any((l) => l.toLowerCase() == 'all');

  bool includes(String code) {
    if (isAllLanguages) return true;
    final lower = LanguageMeta.canonicalCode(code);
    return selectedLanguages.any((l) => l.toLowerCase() == lower);
  }

  LanguageMeta metaFor(String code) => LanguageMeta.fromCode(code);

  LibraryLanguagesState copyWith({
    Set<String>? selectedLanguages,
    List<String>? availableLanguages,
  }) {
    return LibraryLanguagesState(
      selectedLanguages: selectedLanguages ?? this.selectedLanguages,
      availableLanguages: availableLanguages ?? this.availableLanguages,
    );
  }
}

/// Global single source of truth for the library's language filter.
///
/// The Library hub owns this controller. Every content type (books, songs,
/// articles, audio) announces the languages it offers and reads the shared
/// selection so the whole library is filtered by one global choice.
class LibraryLanguagesController extends ChangeNotifier {
  static const String _prefKeyLanguages = 'library_languages';

  LibraryLanguagesState _state = const LibraryLanguagesState();
  LibraryLanguagesState get state => _state;

  final Set<String> _knownLanguages = <String>{};

  LibraryLanguagesController() {
    _restore();
  }

  /// Extracts a shared [LibraryLanguagesController] handed through a GoRouter
  /// `extra` payload (either the controller itself or a map carrying it under
  /// `langController`). Returns null when absent so route-pushed screens can
  /// fall back to a self-owned, prefs-restoring instance.
  static LibraryLanguagesController? fromRouteExtra(Object? extra) {
    if (extra is LibraryLanguagesController) return extra;
    if (extra is Map) {
      final v = extra['langController'];
      return v is LibraryLanguagesController ? v : null;
    }
    return null;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefKeyLanguages);
      if (saved != null && saved.isNotEmpty) {
        final normalized = saved
            .map((c) => LanguageMeta.canonicalCode(c))
            .where((c) => c.isNotEmpty && c != 'all')
            .toSet();
        if (normalized.isEmpty) return;
        _state = _state.copyWith(selectedLanguages: normalized);
        notifyListeners();
        await prefs.setStringList(_prefKeyLanguages, normalized.toList());
      }
    } catch (e) {
      debugPrint('Language restore failed: $e');
    }
  }

  /// Registers a language code offered by a content type. Recomputes the
  /// available-language list whenever the set of known codes changes. Inputs
  /// are canonicalized so full names (`English`) and codes (`en`) collapse to
  /// one entry instead of duplicating the same language.
  void announceLanguages(Iterable<String> codes) {
    var changed = false;
    for (final raw in codes) {
      if (raw.isEmpty) continue;
      final code = LanguageMeta.canonicalCode(raw);
      if (code.isEmpty || code == 'all') continue;
      if (_knownLanguages.add(code)) changed = true;
    }
    if (!changed) return;
    final sorted = _knownLanguages.toList()..sort();
    _state = _state.copyWith(availableLanguages: ['All', ...sorted]);
    notifyListeners();
  }

  /// Applies a new selection and persists it. The selection is canonicalized
  /// so persisted codes stay consistent across content types.
  Future<void> selectLanguages(Set<String> selection) async {
    final normalized = selection
        .map((c) => LanguageMeta.canonicalCode(c))
        .where((c) => c.isNotEmpty)
        .map((c) => c == 'all' ? 'All' : c)
        .toSet();
    final valid = normalized.isEmpty ? {'All'} : normalized;
    _state = _state.copyWith(selectedLanguages: valid);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKeyLanguages, valid.toList());
    } catch (e) {
      debugPrint('Language save failed: $e');
    }
  }

  void reset() {
    selectLanguages({'All'});
  }
}
