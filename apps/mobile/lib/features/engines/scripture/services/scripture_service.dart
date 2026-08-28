import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/api_client.dart';
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
      final items = await _offlineDb.getRandomItems(
        limit,
        bookFilter: bookFilter,
        testamentFilter: testamentFilter,
      );

      if (items.isNotEmpty) {
        const presets = ScriptureThemeCatalog.presets;
        final List<ScriptureCard> fetchedCards = [];

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          final card = ScriptureCard.fromJson(item);

          // If no preset was set, assign one from the catalog
          if (card.backgroundPreset.isEmpty) {
            final presetIdx = (page * limit + i) % presets.length;
            card.customBackgroundPreset = presets[presetIdx].id;
          }

          // Resolve version text using the existing function
          await resolveCardText(card, activeVersionId);
          fetchedCards.add(card);
        }

        _cachedDeck.addAll(fetchedCards);
        return fetchedCards;
      }
      return [];
    } catch (e, st) {
      debugPrint('Error fetching offline scripture cards: $e\n$st');
      return [];
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

    // 2. If requesting WEB (or matched resolved version), return database text
    if (versionId.toUpperCase() == 'WEB' || card.resolvedVersion == versionId) {
      return card.resolvedText;
    }

    return null;
  }

  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    final originalDbText = card.resolvedText;

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

    // 1. Try local/in-memory database first (0ms latency)
    String? text = await _localBible.resolvePassage(
      versionId: versionId,
      bookNumber: reqBookNumber,
      chapter: reqChapter,
      startVerse: reqStartVerse,
      endVerse: reqEndVerse,
    );

    // 2. If not found locally and not default WEB, try Remote Bible API
    if (text == null && versionId.toUpperCase() != 'WEB') {
      text = await _remoteApi.fetchPassage(
        versionId: versionId,
        referenceLabel: reqLabel,
        bookNumber: reqBookNumber,
        chapter: reqChapter,
        startVerse: reqStartVerse,
        endVerse: reqEndVerse,
      );
    }

    // 3. Fallback to authentic verse text from the database
    card.resolvedText = text ?? originalDbText ?? '"For God so loved the world, that he gave his one and only Son..."';
    card.resolvedVersion = text != null ? versionId : (originalDbText != null ? 'WEB' : versionId);
  }
}
