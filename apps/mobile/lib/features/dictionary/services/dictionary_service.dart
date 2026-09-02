import 'package:flutter/foundation.dart';
import '../models/dictionary_entry.dart';
import '../adapters/dictionary_data_adapter.dart';
import '../adapters/sqlite_dictionary_data_adapter.dart';
import '../adapters/web_dictionary_data_adapter.dart';

/// Service querying local offline dictionary SQLite databases or online APIs.
class DictionaryService {
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  
  late final DictionaryDataAdapter _adapter;

  DictionaryService._internal() {
    if (kIsWeb) {
      _adapter = WebDictionaryDataAdapter();
    } else {
      _adapter = SqliteDictionaryDataAdapter();
    }
  }

  /// Automatically detects language code from the characters in [text].
  static String? detectLanguageCode(String text) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta'; // Tamil
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml'; // Malayalam
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'te'; // Telugu
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn'; // Kannada
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi'; // Hindi / Devanagari
    return null;
  }

  /// Cleans punctuation and invalid characters from [raw] word.
  String cleanWord(String raw) {
    return raw
        .replaceAll('_', '')
        .replaceAll(
          RegExp(
            r'''[^\w\s\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F\u0600-\u06FF\u0400-\u04FF]''',
          ),
          '',
        )
        .replaceAll('_', '')
        .trim();
  }

  /// Looks up definitions for a word across active/installed dictionaries.
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode}) async {
    return _adapter.lookupWord(word, preferredLangCode: preferredLangCode);
  }

  /// Closes database handle for [dictId] if opened.
  Future<void> closeDatabase(String dictId) async {
    final adapter = _adapter;
    if (adapter is SqliteDictionaryDataAdapter) {
      await adapter.closeDatabase(dictId);
    }
  }

  /// Closes all active database connections.
  Future<void> closeAll() async {
    final adapter = _adapter;
    if (adapter is SqliteDictionaryDataAdapter) {
      await adapter.closeAll();
    }
  }
}
