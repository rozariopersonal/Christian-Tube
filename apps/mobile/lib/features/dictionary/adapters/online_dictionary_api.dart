import 'package:dio/dio.dart';
import 'package:mobile/features/dictionary/models/dictionary_entry.dart';

class OnlineDictionaryApi {
  /// Queries free online dictionary APIs (FreeDictionaryAPI for English, Wiktionary for global/Indian languages).
  static Future<List<DictionaryEntry>> lookupOnlineApi(String word, {String? langCode}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 3),
    ));

    // 1. English lookup via FreeDictionaryAPI
    if (langCode == null || langCode == 'en') {
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

    // 2. Wiktionary API for Indian and global languages
    final targetLang = langCode ?? 'en';
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

    return [];
  }
}
