import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
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
  final Random _random = Random();

  List<ScriptureCard>? _masterCatalog;
  List<ScriptureCard>? _activeShuffledCatalog;

  Future<void> initialize() async {
    await _localBible.initialize();
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
    if (_masterCatalog == null) {
      try {
        final jsonString =
            await rootBundle.loadString('assets/seed_scriptures.json');
        final List<dynamic> list = jsonDecode(jsonString);
        _masterCatalog = list.map((j) => ScriptureCard.fromJson(j)).toList();
      } catch (_) {
        _masterCatalog = [];
      }
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

  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    // 1. Try local SQLite query first (0ms latency)
    String? text = await _localBible.resolvePassage(
      versionId: versionId,
      bookNumber: card.bookNumber,
      chapter: card.chapter,
      startVerse: card.startVerse,
      endVerse: card.endVerse,
    );

    // 2. Fallback to default bundled version (WEB) if specific language not downloaded
    if (text == null && versionId != 'WEB') {
      text = await _localBible.resolvePassage(
        versionId: 'WEB',
        bookNumber: card.bookNumber,
        chapter: card.chapter,
        startVerse: card.startVerse,
        endVerse: card.endVerse,
      );
    }

    // 3. Fallback to Remote API for online versions
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

    card.resolvedText = text ??
        '“For God so loved the world, that he gave his one and only Son...”';
    card.resolvedVersion = versionId;
  }
}
