const fs = require('fs');

const src = fs.readFileSync('apps/mobile/lib/features/engines/scripture/services/local_bible_service.dart', 'utf8');

const seedMatch = src.match(/void _seedAllPolyglotVerses\(\) \{[\s\S]*?\n  \}/);
if (!seedMatch) {
  console.log('Could not find _seedAllPolyglotVerses');
  process.exit(1);
}

const seedMethod = seedMatch[0];

const content = `import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:mobile/core/api/release_assets.dart';
import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/bible/models/cross_reference.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';
import 'bible_data_adapter.dart';

class WebBibleDataAdapter implements BibleDataAdapter {
  final Map<String, String> _webVerses = {};
  final Set<String> _webInstalledVersions = {};
  final Map<String, Map<String, dynamic>> _webCrossRefs = {};
  bool _webCrossRefsInstalled = false;
  final Map<String, List<Map<String, dynamic>>> _webBackgrounds = {};
  bool _webBackgroundsInstalled = false;
  final Map<String, List<Map<String, dynamic>>> _liveChapterCache = {};

  static const _cdnVersions = {
    'ASV', 'BBE', 'DIODATI', 'ELBERFELDER', 'ELBERFELDER1905', 'HIN_IRV',
    'KAN_IRV', 'KJV', 'LUTHER1545', 'MAL_IRV', 'MARTIN', 'POLGDANSKA',
    'RIVEDUTA', 'SSE', 'STATENVERTALING', 'TAOBVSI', 'TEL_IRV', 'WB', 'WEB', 'YLT'
  };

  @override
  Future<void> initialize() async {
    _seedAllPolyglotVerses();
  }

  @override
  Future<void> close() async {}

  void _addVerse(String versionId, int book, int chapter, int verse, String text) {
    _webVerses['\${versionId}_\${book}_\${chapter}_\$verse'] = text;
  }

  ${seedMethod}

  @override
  Future<List<String>> getInstalledVersionIds() async {
    return BibleDownloadManager.catalog
        .where((v) => _cdnVersions.contains(v.id.toUpperCase()))
        .map((v) => v.id)
        .toList();
  }

  @override
  Future<bool> hasVerses(String versionId) async {
    return BibleDownloadManager.catalog.any((v) => v.id.toLowerCase() == versionId.toLowerCase());
  }

  @override
  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) async {
    final cacheKey = '\${versionId.toLowerCase()}_\${bookName}_\$chapter';
    if (_liveChapterCache.containsKey(cacheKey)) {
      return _liveChapterCache[cacheKey]!;
    }

    final bookNum = BookNameService.englishBookNames.indexOf(bookName) + 1;
    if (bookNum > 0) {
      final urls = ReleaseAssets.urlsFor(
        'bibles/\${versionId.toLowerCase()}/\$bookNum/\$chapter.json',
      );

      final dio = Dio();
      for (final url in urls) {
        try {
          final res = await dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final List<dynamic> list = res.data is String ? jsonDecode(res.data as String) : (res.data as List<dynamic>);
            final List<Map<String, dynamic>> results = list.map((item) {
              return {
                'version_id': versionId,
                'book_name': bookName,
                'book_number': bookNum,
                'chapter': chapter,
                'verse': (item['verse'] as num).toInt(),
                'text': (item['text'] as String?)?.trim() ?? '',
              };
            }).toList();

            _liveChapterCache[cacheKey] = results;
            return results;
          }
        } catch (_) {
          continue;
        }
      }
    }

    List<Map<String, dynamic>> results = [];
    _webVerses.forEach((key, value) {
      final parts = key.split('_');
      if (parts[0] == versionId && parts[2] == chapter.toString()) {
        results.add({
          'verse': int.tryParse(parts[3]) ?? 1,
          'text': value,
        });
      }
    });
    results.sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));
    return results;
  }

  @override
  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final end = endVerse ?? startVerse;
    final List<String> parts = [];
    for (int v = startVerse; v <= end; v++) {
      final key = '\${versionId}_\${bookNumber}_\${chapter}_\$v';
      if (_webVerses.containsKey(key)) {
        parts.add(_webVerses[key]!);
      }
    }
    if (parts.isNotEmpty) return parts.join(' ');
    return null;
  }

  @override
  Future<Map<String, String>> resolvePassages({
    required String versionId,
    required List<(int bookNumber, int chapter, int verse, int? endVerse)> passages,
  }) async {
    final result = <String, String>{};
    for (final (book, chapter, verse, end) in passages) {
      final text = await resolvePassage(
        versionId: versionId,
        bookNumber: book,
        chapter: chapter,
        startVerse: verse,
        endVerse: end,
      );
      if (text != null) result['\${book}_\${chapter}_\$verse'] = text;
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> search(String versionId, String query, {int limit = 100}) async {
    return [];
  }

  @override
  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses) async {
    _webVerses.removeWhere((key, _) => key.startsWith('\${versionId}_'));
    for (final v in verses) {
      final book = v['bookNumber'] ?? v['book_number'];
      final chapter = v['chapter'];
      final verse = v['verse'];
      final text = v['text'];
      _webVerses['\${versionId}_\${book}_\${chapter}_\$verse'] = text;
    }
  }

  @override
  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) async {
    _webInstalledVersions.add(id);
  }

  @override
  Future<void> deleteVersion(String versionId) async {
    _webInstalledVersions.remove(versionId);
    _webVerses.removeWhere((key, _) => key.startsWith('\${versionId}_'));
  }

  @override
  Future<bool> hasCrossReferences() async {
    return _webCrossRefsInstalled;
  }

  @override
  Future<Map<int, List<CrossReference>>> getCrossReferencesForChapter(int bookNumber, int chapter) async {
    final grouped = <int, List<CrossReference>>{};
    _webCrossRefs.forEach((key, r) {
      if (r['bookNumber'] == bookNumber && r['chapter'] == chapter) {
        grouped.putIfAbsent(r['verse'] as int, () => []).add(CrossReference(
              bookNumber: r['refBookNumber'] as int,
              chapter: r['refChapter'] as int,
              verse: r['refVerse'] as int,
              endVerse: r['refEndVerse'] as int?,
              score: r['score'] as int,
            ));
      }
    });
    grouped.forEach((_, list) => list.sort((a, b) => b.score.compareTo(a.score)));
    return grouped;
  }

  @override
  Future<void> insertCrossReferences(List<Map<String, dynamic>> items) async {
    _webCrossRefs.clear();
    for (final r in items) {
      final key = \`\${r['bookNumber']}_\${r['chapter']}_\${r['verse']}\`;
      _webCrossRefs[key] = r;
    }
    _webCrossRefsInstalled = true;
  }

  @override
  Future<void> deleteCrossReferences() async {
    _webCrossRefs.clear();
    _webCrossRefsInstalled = false;
  }

  @override
  Future<bool> hasBackgrounds() async {
    return _webBackgroundsInstalled;
  }

  @override
  Future<Map<int, List<BibleBackgroundNote>>> getBackgroundsForChapter(int bookNumber, int chapter) async {
    final key = '\${bookNumber}_\$chapter';
    final list = _webBackgrounds[key] ?? [];
    final grouped = <int, List<BibleBackgroundNote>>{};
    for (final r in list) {
      final verse = (r['verse'] as int?) ?? 0;
      grouped.putIfAbsent(verse, () => []).add(BibleBackgroundNote.fromMap(r));
    }
    return grouped;
  }

  @override
  Future<void> insertBackgrounds(List<Map<String, dynamic>> items) async {
    _webBackgrounds.clear();
    for (final b in items) {
      final key = \`\${b['bookNumber']}_\${b['chapter']}\`;
      _webBackgrounds.putIfAbsent(key, () => []).add(b);
    }
    _webBackgroundsInstalled = true;
  }

  @override
  Future<void> deleteBackgrounds() async {
    _webBackgrounds.clear();
    _webBackgroundsInstalled = false;
  }
}
`;

fs.writeFileSync('apps/mobile/lib/features/engines/scripture/adapters/web_bible_data_adapter.dart', content);
console.log('Created web_bible_data_adapter.dart');
