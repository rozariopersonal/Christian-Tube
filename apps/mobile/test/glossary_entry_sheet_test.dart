import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/dictionary/models/glossary_entry.dart';
import 'package:mobile/features/dictionary/widgets/glossary_entry_sheet.dart';

void main() {
  const sampleEntry = GlossaryEntry(
    id: 'ta_aaciirvaatam',
    headword: 'ஆசீர்வாதம்',
    transliteration: 'ācīrvātam',
    pos: 'noun',
    posTa: 'பெயர்ச்சொல்',
    category: 'theological',
    glossEn: 'blessing, benediction',
    definitionTa: 'தேவனுடைய தயவு, நன்மை, செழிப்பு மற்றும் விசேஷித்த கிருபையை ஒருவருடைய வாழ்க்கையில் அருளுதல் அல்லது பிரகடனம் செய்தல்.',
    definitionEn: 'The bestowing of divine favor, prosperity, and spiritual grace upon a person or community; a solemn invocation of God\'s benevolence.',
    originalLang: 'Hebrew',
    originalLemma: 'בְּרָכָה',
    originalTranslit: 'berakhah',
    strongs: 'H1293',
    modernEquivalents: ['வாழ்த்து', 'நன்மை', 'ஆசி'],
    forms: ['ஆசீர்வாதத்தை', 'ஆசீர்வாதத்தினால்', 'ஆசீர்வாதங்கள்'],
    notes: 'பழைய ஏற்பாட்டில் தேவனுடைய உடன்படிக்கையின் அடையாளமாகவும், ஆபிரகாமுக்குக் கொடுக்கப்பட்ட வாக்குத்தத்தத்தின் மையமாகவும் விளங்குகிறது.',
    examples: [
      GlossaryExample(
        sentenceTa: 'நான் உன்னை பெரிய ஜாதியாக்கி, உன்னை ஆசீர்வதித்து, உன் பேரைப் பெருமைப்படுத்துவேன்.',
        sentenceEn: 'I will make you into a great nation, and I will bless you; I will make your name great.',
      ),
      GlossaryExample(
        sentenceTa: 'கர்த்தர் உன்னை ஆசீர்வதித்து, உன்னைக் காக்கக்கடவர்.',
        sentenceEn: 'The LORD bless you and keep you.',
      ),
    ],
    seeAlso: ['சாபம் (curse)', 'கிருபை (grace)', 'பரிசுத்தம் (holiness)'],
    refs: ['GEN.12.2', 'NUM.6.24', 'EPH.1.3'],
    occurrenceCount: 202,
    surfaceCount: 88,
    firstRef: 'GEN.12.2',
    lastRef: 'REV.22.14',
  );

  group('GlossaryEntry Model Tests', () {
    test('serializes and deserializes all fields faithfully including first/last refs', () {
      final map = sampleEntry.toMap();
      final reconstituted = GlossaryEntry.fromMap(map);

      expect(reconstituted.id, 'ta_aaciirvaatam');
      expect(reconstituted.headword, 'ஆசீர்வாதம்');
      expect(reconstituted.transliteration, 'ācīrvātam');
      expect(reconstituted.pos, 'noun');
      expect(reconstituted.posTa, 'பெயர்ச்சொல்');
      expect(reconstituted.category, 'theological');
      expect(reconstituted.glossEn, 'blessing, benediction');
      expect(reconstituted.originalLemma, 'בְּרָכָה');
      expect(reconstituted.strongs, 'H1293');
      expect(reconstituted.modernEquivalents, ['வாழ்த்து', 'நன்மை', 'ஆசி']);
      expect(reconstituted.forms.length, 3);
      expect(reconstituted.examples.length, 2);
      expect(reconstituted.examples.first.sentenceTa, contains('பெரிய ஜாதியாக்கி'));
      expect(reconstituted.seeAlso.length, 3);
      expect(reconstituted.occurrenceCount, 202);
      expect(reconstituted.surfaceCount, 88);
      expect(reconstituted.firstRef, 'GEN.12.2');
      expect(reconstituted.lastRef, 'REV.22.14');
    });

    test('creates entry faithfully from unique_words database row with lemma and surface counts', () {
      final dbRow = {
        'id': 483,
        'surface_form': 'வானத்தையும்',
        'pos': 'noun',
        'canonical': 'வானம்',
        'modern_equivalent': 'ஆகாயம்',
        'english_word': 'heavens',
        'definition_ta': 'பூமியின் மேல் உள்ள பரந்த ஆகாயம் அல்லது பரமண்டலம்.',
      };
      final entry = GlossaryEntry.fromUniqueWord(
        dbRow,
        occurrenceCount: 339,
        surfaceCount: 23,
        firstRef: '1:1:1',
        lastRef: '43:1:51',
        refs: ['1:1:1', '1:2:4'],
      );

      expect(entry.headword, 'வானத்தையும்');
      expect(entry.canonical, 'வானம்');
      expect(entry.pos, 'noun');
      expect(entry.posTa, 'பெயர்ச்சொல்');
      expect(entry.englishWord, 'heavens');
      expect(entry.modernEquivalents, ['ஆகாயம்']);
      expect(entry.definitionTa, contains('ஆகாயம்'));
      expect(entry.occurrenceCount, 339);
      expect(entry.surfaceCount, 23);
      expect(entry.firstRef, '1:1:1');
      expect(entry.lastRef, '43:1:51');
      expect(entry.refs, ['1:1:1', '1:2:4']);
      expect(entry.hasDeepLexicon, isFalse);
    });
  });

  group('GlossaryEntrySheet Responsive & Overflow Tests', () {
    Future<void> pumpSheet(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: const Scaffold(
            body: Center(
              child: GlossaryEntrySheet(
                word: 'ஆசீர்வாதம்',
                initialEntry: sampleEntry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders cleanly without overflow at 320dp width (narrow mobile)', (tester) async {
      await pumpSheet(tester, const Size(320, 680));

      expect(find.text('ஆசீர்வாதம்'), findsOneWidget);
      expect(find.text('"blessing, benediction"'), findsOneWidget);
      expect(find.text('בְּרָכָה'), findsOneWidget);
      expect(find.text('வேதாகம உதாரணங்கள்'), findsOneWidget);
      expect(find.text('தொடர்புடைய சொற்கள்'), findsOneWidget);
      expect(find.text('வேதாகமத்தில் 202 இடங்களில் வருகிறது'), findsOneWidget);
      expect(find.text('முதல்: '), findsOneWidget);
      expect(find.text('கடைசி: '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly without overflow at 600dp width (tablet/foldable)', (tester) async {
      await pumpSheet(tester, const Size(600, 900));

      expect(find.text('ஆசீர்வாதம்'), findsOneWidget);
      expect(find.text('Strong\'s H1293'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly without overflow at 840dp width (expanded)', (tester) async {
      await pumpSheet(tester, const Size(840, 1000));

      expect(find.text('ஆசீர்வாதம்'), findsOneWidget);
      expect(find.text('வேதாகமத்தில் 202 இடங்களில் வருகிறது'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders Phase 1 single-view entry with canonical root and modern equivalent chips', (tester) async {
      const phase1Entry = GlossaryEntry(
        id: '483',
        headword: 'வானத்தையும்',
        canonical: 'வானம்',
        pos: 'noun',
        posTa: 'பெயர்ச்சொல்',
        category: 'theological',
        glossEn: 'heavens',
        englishWord: 'heavens',
        definitionTa: 'பூமியின் மேல் உள்ள பரந்த ஆகாயம் அல்லது பரமண்டலம்.',
        definitionEn: '',
        modernEquivalents: ['ஆகாயம்'],
        occurrenceCount: 339,
        surfaceCount: 23,
        firstRef: '1:1:1',
        lastRef: '43:1:51',
        refs: ['1:1:1', '1:2:4'],
      );

      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: const Scaffold(
            body: Center(
              child: GlossaryEntrySheet(
                word: 'வானத்தையும்',
                initialEntry: phase1Entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('வானத்தையும்'), findsOneWidget);
      expect(find.text('"heavens"'), findsOneWidget);
      expect(find.text('வேர்: வானம்'), findsOneWidget);
      expect(find.text('வழக்கு: ஆகாயம்'), findsOneWidget);
      expect(find.text('வேதாகம விளக்கம்'), findsOneWidget);
      expect(find.text('வேதாகமத்தில் 339 இடங்களில் வருகிறது'), findsOneWidget);
      expect(find.textContaining('வேர்ச்சொல்: வானம் (339 முறை) • இவ்வடிவம்: 23 முறை'), findsOneWidget);
      expect(find.text('முதல்: '), findsOneWidget);
      expect(find.text('கடைசி: '), findsOneWidget);
      expect(find.text('மாதிரி வசனங்கள்:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks scripture examples vertically, not side-by-side', (tester) async {
      await pumpSheet(tester, const Size(400, 800));

      final firstEx = find.textContaining('பெரிய ஜாதியாக்கி');
      final secondEx = find.textContaining('காக்கக்கடவர்');

      expect(firstEx, findsOneWidget);
      expect(secondEx, findsOneWidget);

      final firstTop = tester.getTopLeft(firstEx).dy;
      final secondTop = tester.getTopLeft(secondEx).dy;

      // Second example must strictly be positioned vertically below the first example
      expect(secondTop, greaterThan(firstTop));
    });
  });
}
