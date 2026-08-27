import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
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
  final Random _random = Random();

  List<ScriptureCard>? _masterCatalog;
  List<ScriptureCard>? _activeShuffledCatalog;
  bool _isFetchingRemote = false;

  Future<void> initialize() async {
    await _localBible.initialize();
    _fetchRemoteWords();
  }

  Future<void> _fetchRemoteWords() async {
    if (_isFetchingRemote) return;
    _isFetchingRemote = true;
    try {
      final res = await _apiClient.dio.get('/words', queryParameters: {'limit': 100});
      if (res.statusCode == 200 && res.data != null) {
        final dynamic raw = res.data;
        final List<dynamic> items = raw is List ? raw : (raw['items'] ?? []);
        if (items.isNotEmpty) {
          final remoteCards = items
              .whereType<Map<String, dynamic>>()
              .map((j) => ScriptureCard.fromJson(j))
              .toList();

          _masterCatalog ??= [];
          final existingIds = _masterCatalog!.map((c) => c.id).toSet();
          for (final rc in remoteCards) {
            if (!existingIds.contains(rc.id)) {
              _masterCatalog!.insert(0, rc);
            }
          }
          resetRandomDeck();
        }
      }
    } catch (_) {} finally {
      _isFetchingRemote = false;
    }
  }

  /// Shuffles the catalog to ensure a brand new random start on every visit
  void resetRandomDeck() {
    if (_masterCatalog != null && _masterCatalog!.isNotEmpty) {
      _activeShuffledCatalog = List<ScriptureCard>.from(_masterCatalog!)
        ..shuffle(_random);
    }
  }

  Future<List<ScriptureCard>> fetchCards({
    required String activeVersionId,
    int page = 0,
    int limit = 15,
  }) async {
    if (_masterCatalog == null || _masterCatalog!.isEmpty) {
      await _fetchRemoteWords();
    }

    final master = _masterCatalog ?? [];
    if (master.isEmpty) return [];

    // Whenever a new session starts (page == 0) or deck is empty, create a fresh randomized deck
    if (page == 0 || _activeShuffledCatalog == null) {
      _activeShuffledCatalog = List<ScriptureCard>.from(master)..shuffle(_random);
    }

    final catalog = _activeShuffledCatalog!;
    final total = catalog.length;
    final startIndex = (page * limit) % total;
    final List<ScriptureCard> result = [];

    // If paging loops around, reshuffle for endless unpredictable variety
    if (page > 0 && startIndex == 0) {
      catalog.shuffle(_random);
    }

    final presets = ScriptureThemeCatalog.presets;

    for (int i = 0; i < limit; i++) {
      final index = (startIndex + i) % total;
      final original = catalog[index];

      // Assign a random background preset for rich visual diversity
      final presetIndex = _random.nextInt(presets.length);
      final bg = (original.backgroundPreset.isNotEmpty)
          ? original.backgroundPreset
          : presets[presetIndex].id;

      // Clone card so per-card live overrides don't mutate template
      final card = ScriptureCard(
        id: '${original.id}_${page}_${i}_${DateTime.now().microsecondsSinceEpoch}',
        bookNumber: original.bookNumber,
        bookName: original.bookName,
        chapter: original.chapter,
        startVerse: original.startVerse,
        endVerse: original.endVerse,
        referenceLabel: original.referenceLabel,
        category: original.category,
        backgroundPreset: bg,
        tags: original.tags,
      );

      await resolveCardText(card, activeVersionId);
      result.add(card);
    }

    return result;
  }

  String? resolvePassageSync(ScriptureCard card, String versionId) {
    return _localBible.resolvePassageSync(
      versionId: versionId,
      bookNumber: card.bookNumber,
      chapter: card.chapter,
      startVerse: card.startVerse,
      endVerse: card.endVerse,
    );
  }

  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    // 1. Try local/in-memory database first (0ms latency)
    String? text = await _localBible.resolvePassage(
      versionId: versionId,
      bookNumber: card.bookNumber,
      chapter: card.chapter,
      startVerse: card.startVerse,
      endVerse: card.endVerse,
    );

    // 2. If not found locally, try Remote Bible API for the requested versionId
    if (text == null) {
      text = await _remoteApi.fetchPassage(
        versionId: versionId,
        referenceLabel: card.referenceLabel,
        bookNumber: card.bookNumber,
        chapter: card.chapter,
        startVerse: card.startVerse,
        endVerse: card.endVerse,
      );
    }

    // 3. Fallback to default bundled version (WEB) only if everything else failed
    if (text == null && versionId != 'WEB') {
      text = await _localBible.resolvePassage(
        versionId: 'WEB',
        bookNumber: card.bookNumber,
        chapter: card.chapter,
        startVerse: card.startVerse,
        endVerse: card.endVerse,
      );
    }

    card.resolvedText = text ??
        '“For God so loved the world, that he gave his one and only Son...”';
    card.resolvedVersion = versionId;
  }
}
