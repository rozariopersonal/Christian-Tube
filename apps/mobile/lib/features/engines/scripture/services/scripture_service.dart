import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
import 'local_bible_service.dart';
import 'offline_feed_database.dart';
import 'remote_bible_api_service.dart';
import 'saved_scripture_service.dart';

class ScriptureService {
  static final ScriptureService _instance = ScriptureService._internal();
  factory ScriptureService() => _instance;
  ScriptureService._internal();

  final LocalBibleService _localBible = LocalBibleService();
  final RemoteBibleApiService _remoteApi = RemoteBibleApiService();
  final OfflineFeedDatabase _offlineDb = OfflineFeedDatabase();

  final List<ScriptureCard> _cachedDeck = [];

  Future<void> initialize() async {
    await _localBible.initialize();
    await _offlineDb.initialize();
  }

  Future<List<String>> getInstalledVersionIds() async {
    final ids = await _localBible.getInstalledVersionIds();
    final usable = <String>[];
    for (final id in ids) {
      if (await _localBible.hasVerses(id)) {
        usable.add(id);
      }
    }
    return usable;
  }

  void resetRandomDeck() {
    _cachedDeck.clear();
  }

  Future<List<ScriptureCard>> fetchCards({
    required String activeVersionId,
    int page = 0,
    int limit = 15,
    String? category,
    String? bookFilter,
    String? testamentFilter,
    List<String>? categories,
    List<String>? tags,
    String order = 'random',
  }) async {
    try {
      List<String>? effectiveCategories;
      List<String>? effectiveTags = tags != null ? List<String>.from(tags) : null;

      final inputCategories =
          categories ?? (category != null ? [category] : null);
      if (inputCategories != null && inputCategories.isNotEmpty) {
        effectiveCategories = [];
        for (final cat in inputCategories) {
          if (cat == 'prayer') {
            effectiveCategories.add('prayer');
            effectiveCategories.add('consecration');
          } else if (cat == 'courage') {
            effectiveTags ??= [];
            if (!effectiveTags.contains('courage')) {
              effectiveTags.add('courage');
            }
          } else {
            effectiveCategories.add(cat);
          }
        }
      }

      if (order == 'bookmarked') {
        await SavedScriptureService().initialize();
        var saved = SavedScriptureService().getSavedCards();
        if (bookFilter != null && bookFilter.isNotEmpty && bookFilter != 'All Books') {
          saved = saved.where((c) => c.bookName == bookFilter).toList();
        }
        if (testamentFilter != null && testamentFilter.isNotEmpty && testamentFilter != 'All') {
          if (testamentFilter == 'Old Testament') {
            saved = saved.where((c) => c.bookNumber <= 39).toList();
          } else if (testamentFilter == 'New Testament') {
            saved = saved.where((c) => c.bookNumber >= 40).toList();
          }
        }
        final filterCats = effectiveCategories;
        final filterTags = effectiveTags;
        if (filterCats != null &&
            filterCats.isNotEmpty &&
            filterTags != null &&
            filterTags.isNotEmpty) {
          saved = saved
              .where((c) =>
                  filterCats.contains(c.category) ||
                  c.tags.any((t) => filterTags.contains(t)))
              .toList();
        } else if (filterCats != null && filterCats.isNotEmpty) {
          saved = saved.where((c) => filterCats.contains(c.category)).toList();
        } else if (filterTags != null && filterTags.isNotEmpty) {
          saved = saved
              .where((c) => c.tags.any((t) => filterTags.contains(t)))
              .toList();
        }
        final start = page * limit;
        if (start >= saved.length) return [];
        final pageCards = saved.skip(start).take(limit).toList();
        for (final card in pageCards) {
          await resolveCardText(card, activeVersionId);
        }
        return pageCards;
      }

      // Exclude already-served cards (bounded window) so infinite-scroll pages
      // never repeat verses until the deck is intentionally reset.
      final seenIds = _cachedDeck.length > 800
          ? _cachedDeck
              .skip(_cachedDeck.length - 800)
              .map((c) => c.id)
              .whereType<String>()
              .toSet()
          : _cachedDeck.map((c) => c.id).whereType<String>().toSet();

      final items = await _offlineDb.getRandomItems(
        limit,
        offset: page * limit,
        bookFilter: bookFilter,
        testamentFilter: testamentFilter,
        categoryFilter: effectiveCategories,
        tagFilter: effectiveTags,
        order: order,
        excludeIds: seenIds.toList(),
      );

      if (items.isNotEmpty) {
        const presets = ScriptureThemeCatalog.presets;
        final eagerCount = items.length > 3 ? 3 : items.length;
        final eagerItems = items.take(eagerCount).toList();
        final remainingItems = items.skip(eagerCount).toList();

        final eagerCards = await Future.wait(
          eagerItems.asMap().entries.map((entry) async {
            final i = entry.key;
            final item = entry.value;
            final card = ScriptureCard.fromJson(item);

            if (card.backgroundPreset.isEmpty) {
              final presetIdx = (page * limit + i) % presets.length;
              card.customBackgroundPreset = presets[presetIdx].id;
            }

            await resolveCardText(card, activeVersionId);
            return card;
          }),
        );

        final List<ScriptureCard> fetchedCards = List.from(eagerCards);

        for (var i = 0; i < remainingItems.length; i++) {
          final item = remainingItems[i];
          final card = ScriptureCard.fromJson(item);
          final globalIdx = eagerCount + i;
          if (card.backgroundPreset.isEmpty) {
            final presetIdx = (page * limit + globalIdx) % presets.length;
            card.customBackgroundPreset = presets[presetIdx].id;
          }
          fetchedCards.add(card);
          unawaited(resolveCardText(card, activeVersionId));
        }

        _cachedDeck.addAll(fetchedCards);
        return fetchedCards;
      }
      return [];
    } catch (e, st) {
      debugPrint('Error fetching offline scripture cards: $e\n$st');
      rethrow;
    }
  }

  String? resolvePassageSync(ScriptureCard card, String versionId) {
    int reqBookNumber = card.bookNumber;
    int reqChapter = card.chapter;
    int reqStartVerse = card.startVerse;
    int? reqEndVerse = card.endVerse;

    if (card.verseMappings != null && card.verseMappings!.containsKey(versionId)) {
      final mapping = card.verseMappings![versionId];
      if (mapping is Map) {
        reqBookNumber = mapping['bookNumber'] ?? reqBookNumber;
        reqChapter = mapping['chapter'] ?? reqChapter;
        reqStartVerse = mapping['startVerse'] ?? reqStartVerse;
        reqEndVerse = mapping['endVerse'] ?? reqEndVerse;
      }
    }

    // 1. Try local polyglot
    final localText = _localBible.resolvePassageSync(
      versionId: versionId,
      bookNumber: reqBookNumber,
      chapter: reqChapter,
      startVerse: reqStartVerse,
      endVerse: reqEndVerse,
    );
    if (localText != null) return localText;

    // 2. If card's already resolved text matches the requested version, return it
    if (card.resolvedVersion != null &&
        card.resolvedVersion!.toUpperCase() == versionId.toUpperCase()) {
      return card.resolvedText;
    }

    return null;
  }

  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    final originalDbText = card.resolvedText;
    final text = await _fetchTextForVersion(card, versionId);

    if (text != null && text.isNotEmpty) {
      card.resolvedText = text;
      card.resolvedVersion = versionId;
    } else if (card.resolvedVersion == null && originalDbText != null) {
      card.resolvedText = originalDbText;
    }
  }

  Future<String?> _fetchTextForVersion(ScriptureCard card, String versionId) async {
    // Apply verse mapping overrides if they exist for this version
    int reqBookNumber = card.bookNumber;
    int reqChapter = card.chapter;
    int reqStartVerse = card.startVerse;
    int? reqEndVerse = card.endVerse;
    String reqLabel = card.referenceLabel;

    if (card.verseMappings != null && card.verseMappings!.containsKey(versionId)) {
      final mapping = card.verseMappings![versionId];
      if (mapping is Map) {
        reqBookNumber = mapping['bookNumber'] ?? reqBookNumber;
        reqChapter = mapping['chapter'] ?? reqChapter;
        reqStartVerse = mapping['startVerse'] ?? reqStartVerse;
        reqEndVerse = mapping['endVerse'] ?? reqEndVerse;
        reqLabel = mapping['referenceLabel'] ?? reqLabel;
      }
    }

    // Try local/in-memory database (0ms latency)
    String? text = await _localBible.resolvePassage(
      versionId: versionId,
      bookNumber: reqBookNumber,
      chapter: reqChapter,
      startVerse: reqStartVerse,
      endVerse: reqEndVerse,
    );

    // Feed metadata contains only references (no text), so fall back to the
    // remote Bible API when the local database lacks this passage. This is used
    // solely for English translations that the API can serve in their own
    // language; non-English versions resolve only from installed local bibles
    // so the correct-language text is never substituted with English.
    if (text == null && _remoteApi.supportsVersion(versionId)) {
      text = await _remoteApi.fetchPassage(
        versionId: versionId,
        referenceLabel: reqLabel,
        bookNumber: reqBookNumber,
        chapter: reqChapter,
        startVerse: reqStartVerse,
        endVerse: reqEndVerse,
      );
    }
    return text;
  }

  /// Resolves [versionId] text onto [card] as the comparison column. Never
  /// substitutes English for non-English versions (same guard as
  /// [resolveCardText]); null result leaves the comparison column empty.
  Future<void> resolveCardComparisonText(
    ScriptureCard card,
    String versionId,
  ) async {
    final text = await _fetchTextForVersion(card, versionId);
    card.comparisonText = text;
    card.comparisonVersion = text != null ? versionId : null;
  }
}
