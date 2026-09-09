import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/shared/services/library_languages_controller.dart';
import 'package:mobile/shared/ui/language_meta.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanguageMeta.canonicalCode', () {
    test('maps full English names to their ISO codes', () {
      expect(LanguageMeta.canonicalCode('English'), 'en');
      expect(LanguageMeta.canonicalCode('Tamil'), 'ta');
      expect(LanguageMeta.canonicalCode('Telugu'), 'te');
      expect(LanguageMeta.canonicalCode('Hindi'), 'hi');
      expect(LanguageMeta.canonicalCode('Kannada'), 'kn');
      expect(LanguageMeta.canonicalCode('Malayalam'), 'ml');
    });

    test('maps native names to their ISO codes', () {
      expect(LanguageMeta.canonicalCode('Deutsch'), 'de');
      expect(LanguageMeta.canonicalCode('Français'), 'fr');
      expect(LanguageMeta.canonicalCode('Português'), 'pt');
      expect(LanguageMeta.canonicalCode('Italiano'), 'it');
      expect(LanguageMeta.canonicalCode('मराठी'), 'mr');
      expect(LanguageMeta.canonicalCode('தமிழ்'), 'ta');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(LanguageMeta.canonicalCode('  FrAnÇaIs  '), 'fr');
      expect(LanguageMeta.canonicalCode('TA'), 'ta');
      expect(LanguageMeta.canonicalCode('All'), 'all');
    });

    test('passes through unrecognized values lowercased', () {
      expect(LanguageMeta.canonicalCode('zz'), 'zz');
      expect(LanguageMeta.canonicalCode('Gerbil'), 'gerbil');
    });
  });

  group('LanguageMeta.fromCode fallback', () {
    test('never renders an unknown raw code in shouting uppercase', () {
      final meta = LanguageMeta.fromCode('zz');
      expect(meta.englishName, 'zz');
      expect(meta.nativeName, isEmpty);
    });

    test('shows a registered catalog language name instead of its code', () {
      LanguageMeta.registerLanguage('gu', englishName: 'Gujarati');
      try {
        final meta = LanguageMeta.fromCode('gu');
        expect(meta.englishName, 'Gujarati');
        expect(LanguageMeta.canonicalCode('gujarati'), 'gu');
      } finally {
        // No teardown API; re-registering later is idempotent for the same
        // value, and tests use distinct codes.
      }
    });

    test('keeps richer static metadata for well-known codes', () {
      LanguageMeta.registerLanguage('ta', englishName: 'Wrong');
      // Static metadata wins over the dynamic registration.
      expect(LanguageMeta.fromCode('ta').englishName, 'Tamil');
    });
  });

  group('LibraryLanguagesController canonicalization', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('merge codes and full names so a language is not announced twice',
        () async {
      final lang = LibraryLanguagesController();
      lang.announceLanguages(['en', 'ta', 'hi']);
      // Audio announces full names for the same languages.
      lang.announceLanguages(['English', 'Tamil', 'Hindi', 'Italiano']);

      final available = lang.state.availableLanguages.join(',').toLowerCase();
      expect(available, isNot(contains('english')));
      final set = lang.state.availableLanguages.toSet();
      expect(set.length, lang.state.availableLanguages.length,
          reason: 'availability list must not contain duplicates');
      expect(set, containsAll(['All', 'en', 'ta', 'hi', 'it']));

      lang.dispose();
    });

    test('select persists canonical codes and filters by name input', () async {
      final lang = LibraryLanguagesController();
      lang.announceLanguages(['English', 'Tamil']);

      await lang.selectLanguages({'tamil'});
      expect(lang.state.selectedLanguages, {'ta'});

      // A full-name label in content still matches the canonical selection.
      expect(lang.state.includes('Tamil'), isTrue);
      expect(lang.state.includes('ta'), isTrue);
      expect(lang.state.includes('en'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('library_languages'), ['ta']);
      lang.dispose();
    });

    test('restore migrates legacy name-based values to codes', () async {
      SharedPreferences.setMockInitialValues({
        'library_languages': ['Tamil', 'English'],
      });
      final lang = LibraryLanguagesController();
      await Future<void>.delayed(Duration.zero);

      expect(lang.state.selectedLanguages, {'ta', 'en'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('library_languages'), containsAll(['ta', 'en']));
      lang.dispose();
    });
  });
}