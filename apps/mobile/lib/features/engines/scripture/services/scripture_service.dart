import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/api_client.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
import 'local_bible_service.dart';
import 'remote_bible_api_service.dart';

class ScriptureService {
  static final ScriptureService _instance = ScriptureService._internal();
  factory ScriptureService() => _instance;
  ScriptureService._internal();

  final LocalBibleService _localBible = LocalBibleService();
  final RemoteBibleApiService _remoteApi = RemoteBibleApiService();
  final ApiClient _apiClient = ApiClient();

  final List<ScriptureCard> _cachedDeck = [];

  Future<void> initialize() async {
    await _localBible.initialize();
  }

  void resetRandomDeck() {
    _cachedDeck.clear();
  }

  Future<List<ScriptureCard>> fetchCards({
    required String activeVersionId,
    int page = 0,
    int limit = 15,
    String? category,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page + 1,
        'limit': limit,
      };
      if (category != null && category.isNotEmpty && category.toLowerCase() != 'all') {
        queryParams['category'] = category;
      }

      final res = await _apiClient.dio.get('/words', queryParameters: queryParams);

      if (res.statusCode == 200 && res.data != null) {
        final dynamic raw = res.data;
        final List<dynamic> items = raw is List ? raw : (raw['items'] ?? []);

        if (items.isNotEmpty) {
          const presets = ScriptureThemeCatalog.presets;
          final List<ScriptureCard> fetchedCards = [];

          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is Map<String, dynamic>) {
              final card = ScriptureCard.fromJson(item);

              // If no preset was set, assign one from the catalog
              if (card.backgroundPreset.isEmpty) {
                final presetIdx = (page * limit + i) % presets.length;
                card.customBackgroundPreset = presets[presetIdx].id;
              }

              // Resolve version text
              await resolveCardText(card, activeVersionId);
              fetchedCards.add(card);
            }
          }

          if (fetchedCards.isNotEmpty) {
            _cachedDeck.addAll(fetchedCards);
            return fetchedCards;
          }
        }
      }
    } catch (e) {
      debugPrint('ScriptureService fetchCards network error: $e');
    }

    // Offline / Cache Fallback
    if (_cachedDeck.isNotEmpty) {
      final startIndex = (page * limit) % _cachedDeck.length;
      final List<ScriptureCard> fallbackList = [];
      for (int i = 0; i < limit; i++) {
        final idx = (startIndex + i) % _cachedDeck.length;
        final cached = _cachedDeck[idx];
        await resolveCardText(cached, activeVersionId);
        fallbackList.add(cached);
      }
      return fallbackList;
    }

    return [];
  }

  String? resolvePassageSync(ScriptureCard card, String versionId) {
    // 1. Try local polyglot
    final localText = _localBible.resolvePassageSync(
      versionId: versionId,
      bookNumber: card.bookNumber,
      chapter: card.chapter,
      startVerse: card.startVerse,
      endVerse: card.endVerse,
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

    // 1. Try local/in-memory database first (0ms latency)
    String? text = await _localBible.resolvePassage(
      versionId: versionId,
      bookNumber: card.bookNumber,
      chapter: card.chapter,
      startVerse: card.startVerse,
      endVerse: card.endVerse,
    );

    // 2. If not found locally and not default WEB, try Remote Bible API
    if (text == null && versionId.toUpperCase() != 'WEB') {
      text = await _remoteApi.fetchPassage(
        versionId: versionId,
        referenceLabel: card.referenceLabel,
        bookNumber: card.bookNumber,
        chapter: card.chapter,
        startVerse: card.startVerse,
        endVerse: card.endVerse,
      );
    }

    // 3. Fallback to authentic verse text from the database
    card.resolvedText = text ?? originalDbText ?? '"For God so loved the world, that he gave his one and only Son..."';
    card.resolvedVersion = text != null ? versionId : (originalDbText != null ? 'WEB' : versionId);
  }
}
