import 'package:flutter/foundation.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
import 'local_bible_service.dart';
import 'offline_feed_database.dart';
import 'remote_bible_api_service.dart';

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
  }) async {
    try {
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
        bookFilter: bookFilter,
        testamentFilter: testamentFilter,
        excludeIds: seenIds.toList(),
      );

      if (items.isNotEmpty) {
        const presets = ScriptureThemeCatalog.presets;
        final List<ScriptureCard> fetchedCards = await Future.wait(
          items.asMap().entries.map((entry) async {
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

    // 2. If requesting WEB (or matched resolved version), return known text
    if (versionId.toUpperCase() == 'WEB' ||
        (card.resolvedVersion != null &&
            card.resolvedVersion!.toUpperCase() == versionId.toUpperCase())) {
      return card.resolvedText;
    }

    return null;
  }

  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    final originalDbText = card.resolvedText;
    final text = await _fetchTextForVersion(card, versionId);

    card.resolvedText = text ?? originalDbText;
    card.resolvedVersion =
        text != null ? versionId : (originalDbText != null ? card.resolvedVersion : null);
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
