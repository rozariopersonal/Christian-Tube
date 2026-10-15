import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/language_meta.dart';

/// Immutable snapshot of the global library language filter.
@immutable
class LibraryLanguagesState {
  final Set<String> selectedLanguages;

  /// Every language code available across the whole library, plus 'All'.
  final List<String> availableLanguages;

  /// Recent languages ordered by most recent selection (excluding 'All').
  final List<String> recentLanguages;

  /// Frequency counter for each selected language code.
  final Map<String, int> usageCounts;

  const LibraryLanguagesState({
    this.selectedLanguages = const {'All'},
    this.availableLanguages = const ['All'],
    this.recentLanguages = const [],
    this.usageCounts = const {},
  });

  bool get isAllLanguages => selectedLanguages.isEmpty ||
      selectedLanguages.any((l) => l.toLowerCase() == 'all');

  bool includes(String code) {
    if (isAllLanguages) return true;
    final lower = LanguageMeta.canonicalCode(code);
    return selectedLanguages.any((l) => l.toLowerCase() == lower);
  }

  LanguageMeta metaFor(String code) => LanguageMeta.fromCode(code);

  /// Frequently used language codes ordered by count descending.
  List<String> get frequentlyUsedLanguages {
    final list = usageCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.map((e) => e.key).toList();
  }

  LibraryLanguagesState copyWith({
    Set<String>? selectedLanguages,
    List<String>? availableLanguages,
    List<String>? recentLanguages,
    Map<String, int>? usageCounts,
  }) {
    return LibraryLanguagesState(
      selectedLanguages: selectedLanguages ?? this.selectedLanguages,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      recentLanguages: recentLanguages ?? this.recentLanguages,
      usageCounts: usageCounts ?? this.usageCounts,
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
  static const String _prefKeyRecent = 'library_languages_recent';
  static const String _prefKeyUsage = 'library_languages_usage';

  static final LibraryLanguagesController instance =
      LibraryLanguagesController._internal();

  LibraryLanguagesState _state = const LibraryLanguagesState();
  LibraryLanguagesState get state => _state;

  final Set<String> _knownLanguages = <String>{};
  final bool _isSingleton;
  bool _isDisposed = false;

  LibraryLanguagesController([Set<String>? initial])
      : _isSingleton = false {
    if (initial != null) {
      _state = _state.copyWith(selectedLanguages: initial);
    } else {
      _restore();
    }
  }

  LibraryLanguagesController._internal()
      : _isSingleton = true {
    _restore();
  }

  @visibleForTesting
  static void resetInstanceForTesting() {
    instance.reset();
  }

  /// Extracts a shared [LibraryLanguagesController] handed through a GoRouter
  /// `extra` payload (either the controller itself or a map carrying it under
  /// `langController`). Returns the global [instance] when absent.
  static LibraryLanguagesController fromRouteExtra(Object? extra) {
    if (extra is LibraryLanguagesController) return extra;
    if (extra is Map) {
      final v = extra['langController'];
      if (v is LibraryLanguagesController) return v;
    }
    return instance;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefKeyLanguages);
      final recent = prefs.getStringList(_prefKeyRecent) ?? [];
      final usageRaw = prefs.getString(_prefKeyUsage);
      Map<String, int> usage = {};
      if (usageRaw != null && usageRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(usageRaw) as Map<String, dynamic>;
          usage = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
        } catch (_) {}
      }

      Set<String>? normalizedSelection;
      if (saved != null && saved.isNotEmpty) {
        final normalized = saved
            .map((c) => LanguageMeta.canonicalCode(c))
            .where((c) => c.isNotEmpty && c != 'all')
            .toSet();
        if (normalized.isNotEmpty) {
          normalizedSelection = normalized;
          if (!setEquals(normalized, saved.toSet())) {
            await prefs.setStringList(_prefKeyLanguages, normalized.toList());
          }
        }
      }

      if (_isDisposed) return;
      _state = _state.copyWith(
        selectedLanguages: normalizedSelection ?? _state.selectedLanguages,
        recentLanguages: recent,
        usageCounts: usage,
      );
      notifyListeners();
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

    final newRecent = List<String>.from(_state.recentLanguages);
    final newUsage = Map<String, int>.from(_state.usageCounts);

    for (final code in valid) {
      if (code.toLowerCase() == 'all') continue;
      newRecent.remove(code);
      newRecent.insert(0, code);
      newUsage[code] = (newUsage[code] ?? 0) + 1;
    }
    while (newRecent.length > 5) {
      newRecent.removeLast();
    }

    _state = _state.copyWith(
      selectedLanguages: valid,
      recentLanguages: newRecent,
      usageCounts: newUsage,
    );
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKeyLanguages, valid.toList());
      await prefs.setStringList(_prefKeyRecent, newRecent);
      await prefs.setString(_prefKeyUsage, jsonEncode(newUsage));
    } catch (e) {
      debugPrint('Language save failed: $e');
    }
  }

  void reset() {
    selectLanguages({'All'});
  }

  @override
  // ignore: must_call_super
  void dispose() {
    _isDisposed = true;
    if (_isSingleton) {
      // Singleton controller persists across the application lifecycle.
      return;
    }
    super.dispose();
  }
}

