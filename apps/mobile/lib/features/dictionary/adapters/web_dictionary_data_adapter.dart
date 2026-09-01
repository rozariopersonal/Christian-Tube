import 'package:mobile/features/dictionary/models/dictionary_entry.dart';
import 'dictionary_data_adapter.dart';
import 'online_dictionary_api.dart';

class WebDictionaryDataAdapter implements DictionaryDataAdapter {
  @override
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode}) async {
    return OnlineDictionaryApi.lookupOnlineApi(word, langCode: preferredLangCode);
  }
}
