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
  );

  group('GlossaryEntry Model Tests', () {
    test('serializes and deserializes all 17 fields faithfully', () {
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
