import 'package:mobile/features/dictionary/models/dictionary_entry.dart';

abstract class DictionaryDataAdapter {
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode});
}
