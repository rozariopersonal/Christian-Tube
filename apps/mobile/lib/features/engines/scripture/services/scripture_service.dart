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
  bool _isFetchingRemote = false;

  Future<void> initialize() async {
    await _localBible.initialize();
    await _fetchRemoteWords();
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

          _masterCatalog = remoteCards;
        }
      }
    } catch (_) {} finally {
      _isFetchingRemote = false;
    }
  }

  void resetRandomDeck() {
    // Keep feed stable
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

    final total = master.length;
    final startIndex = (page * limit) % total;
    final List<ScriptureCard> result = [];

    final presets = ScriptureThemeCatalog.presets;

    for (int i = 0; i < limit; i++) {
      final index = (startIndex + i) % total;
      final original = master[index];

      final presetIndex = index % presets.length;
      final bg = (original.backgroundPreset.isNotEmpty)
          ? original.backgroundPreset
          : presets[presetIndex].id;

      final card = ScriptureCard(
        id: '${original.id}_$index',
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
