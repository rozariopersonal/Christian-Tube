import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/features/dictionary/models/dictionary_entry.dart';
import 'sqlite_dictionary_data_adapter.dart';

class OnlineDictionaryApi {
  /// Queries free online dictionary APIs (FreeDictionaryAPI for English, Wiktionary for global/Indian languages).
  static Future<List<DictionaryEntry>> lookupOnlineApi(String word, {String? langCode}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5),
    ));

    final targetLang = langCode ?? SqliteDictionaryDataAdapter.detectLanguageCode(word) ?? 'en';

    // 1. English lookup via FreeDictionaryAPI
    if (targetLang == 'en') {
      try {
        final res = await dio.get<dynamic>(
          'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word)}',
          options: Options(
            responseType: ResponseType.json,
          ),
        );
        if (res.statusCode == 200 && res.data is List && (res.data as List).isNotEmpty) {
          final List<dynamic> entries = res.data as List<dynamic>;
          final list = <DictionaryEntry>[];
          for (final item in entries) {
            final hw = item['word'] as String? ?? word;
            final phonetic = item['phonetic'] as String? ?? '';
            final meanings = item['meanings'] as List<dynamic>? ?? [];
            for (final m in meanings) {
              final pos = m['partOfSpeech'] as String? ?? '';
              final defs = m['definitions'] as List<dynamic>? ?? [];
              for (final d in defs) {
                final def = d['definition'] as String? ?? '';
                final ex = d['example'] as String? ?? '';
                if (def.isNotEmpty) {
                  list.add(DictionaryEntry(
                    headword: hw,
                    partOfSpeech: pos,
                    phonetic: phonetic,
                    definition: def,
                    examples: ex,
                    source: 'English Dictionary (Live)',
                  ));
                }
                if (list.length >= 5) break;
              }
              if (list.length >= 5) break;
            }
          }
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // 2. Wiktionary REST API for standard European languages (fr, es, de, etc.)
    const restSupportedLangs = {'es', 'fr', 'de', 'pt', 'ru', 'it', 'en'};
    if (restSupportedLangs.contains(targetLang)) {
      try {
        final res = await dio.get<dynamic>(
          'https://$targetLang.wiktionary.org/api/rest_v1/page/definition/${Uri.encodeComponent(word)}',
          options: Options(
            responseType: ResponseType.json,
          ),
        );
        if (res.statusCode == 200 && res.data is Map) {
          final Map<String, dynamic> data = res.data as Map<String, dynamic>;
          final list = <DictionaryEntry>[];
          for (final key in data.keys) {
            final langItems = data[key] as List<dynamic>? ?? [];
            for (final item in langItems) {
              final pos = item['partOfSpeech'] as String? ?? '';
              final defs = item['definitions'] as List<dynamic>? ?? [];
              for (final d in defs) {
                final defText = (d['definition'] as String? ?? '')
                    .replaceAll(RegExp(r'<[^>]*>'), '');
                if (defText.isNotEmpty) {
                  list.add(DictionaryEntry(
                    headword: word,
                    partOfSpeech: pos,
                    phonetic: '',
                    definition: defText,
                    examples: '',
                    source: 'Wiktionary (Live)',
                  ));
                }
                if (list.length >= 4) break;
              }
            }
          }
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // 3. Robust MediaWiki Action API with CORS support (origin=*) & Morphological Stemming
    try {
      final stems = targetLang == 'ta'
          ? SqliteDictionaryDataAdapter.stemTamil(word)
          : <String>[];
      final candidateTitles = <String>[word];
      for (final s in stems) {
        if (!candidateTitles.contains(s)) candidateTitles.add(s);
        if (candidateTitles.length >= 5) break;
      }

      final titlesQuery = candidateTitles.join('|');
      final headers = <String, String>{};
      if (!kIsWeb) {
        headers['User-Agent'] = 'ChristianTubeApp/1.0 (https://github.com/rozariopersonal/Christian-Tube; contact@example.com)';
      }

      final res = await dio.get<dynamic>(
        'https://$targetLang.wiktionary.org/w/api.php',
        queryParameters: {
          'action': 'query',
          'prop': 'extracts',
          'explaintext': '1',
          'format': 'json',
          'origin': '*',
          'titles': titlesQuery,
        },
        options: Options(
          responseType: ResponseType.json,
          headers: headers.isNotEmpty ? headers : null,
        ),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final query = res.data['query'] as Map<String, dynamic>?;
        final pages = query?['pages'] as Map<String, dynamic>?;
        if (pages != null && pages.isNotEmpty) {
          final entries = <DictionaryEntry>[];
          for (final candidate in candidateTitles) {
            final match = pages.values.firstWhere(
              (p) => p is Map && p['title'] == candidate && p['missing'] == null && (p['extract'] as String? ?? '').trim().isNotEmpty,
              orElse: () => null,
            ) as Map<String, dynamic>?;

            if (match != null) {
              final title = match['title'] as String? ?? word;
              final rawExtract = match['extract'] as String? ?? '';
              final cleanDef = _formatExtract(rawExtract);
              if (cleanDef.isNotEmpty) {
                entries.add(
                  DictionaryEntry(
                    headword: title,
                    partOfSpeech: '',
                    phonetic: '',
                    definition: cleanDef,
                    examples: '',
                    source: 'Wiktionary (Online)',
                  ),
                );
                break;
              }
            }
          }
          if (entries.isNotEmpty) return entries;
        }
      }
    } catch (_) {}

    return [];
  }

  static String _formatExtract(String raw) {
    final lines = raw.split('\n');
    final content = <String>[];
    for (var l in lines) {
      l = l.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('==')) continue;
      if (l.startsWith('{') || l.startsWith('}')) continue;
      if (l.startsWith('===') || l.startsWith('----')) continue;
      content.add(l);
      if (content.length >= 10) break;
    }
    if (content.isEmpty) return raw.trim();
    return content.join('\n');
  }
}
