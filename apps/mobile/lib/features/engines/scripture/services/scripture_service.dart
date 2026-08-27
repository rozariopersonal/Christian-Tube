import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/scripture_card.dart';
import 'local_bible_service.dart';
import 'remote_bible_api_service.dart';

class ScriptureService {
  static final ScriptureService _instance = ScriptureService._internal();
  factory ScriptureService() => _instance;
  ScriptureService._internal();

  final LocalBibleService _localBible = LocalBibleService();
  final RemoteBibleApiService _remoteApi = RemoteBibleApiService();

  List<ScriptureCard>? _cachedCatalog;

  Future<void> initialize() async {
    await _localBible.initialize();
  }

  Future<List<ScriptureCard>> fetchCards({
    required String activeVersionId,
    int page = 0,
    int limit = 15,
  }) async {
    if (_cachedCatalog == null) {
      try {
        final jsonString =
            await rootBundle.loadString('assets/seed_scriptures.json');
        final List<dynamic> list = jsonDecode(jsonString);
        _cachedCatalog = list.map((j) => ScriptureCard.fromJson(j)).toList();
      } catch (_) {
        _cachedCatalog = [];
      }
    }

    final catalog = _cachedCatalog ?? [];
    if (catalog.isEmpty) return [];

    // Paginate through catalog (with loop around for endless swipe feel)
    final total = catalog.length;
    final startIndex = (page * limit) % total;
    final List<ScriptureCard> result = [];

    for (int i = 0; i < limit; i++) {
      final index = (startIndex + i) % total;
      final original = catalog[index];
      // Clone card so per-card live overrides don't mutate template
      final card = ScriptureCard(
        id: '${original.id}_${page}_$i',
        bookNumber: original.bookNumber,
        bookName: original.bookName,
        chapter: original.chapter,
        startVerse: original.startVerse,
        endVerse: original.endVerse,
        referenceLabel: original.referenceLabel,
        category: original.category,
        backgroundPreset: original.backgroundPreset,
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
