import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/controllers/bible_search_controller.dart';
import 'package:mobile/features/bible/models/bible_search_hit.dart';
import 'package:mobile/features/bible/screens/bible_search_screen.dart';
import 'package:mobile/features/bible/services/bible_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBibleSearchService extends BibleSearchService {
  final List<BibleSearchHit> stubHits;
  String? lastQuery;

  _FakeBibleSearchService(this.stubHits) : super(dio: Dio());

  @override
  Future<List<BibleSearchHit>> search(
    String query, {
    String? versionId,
    int limit = 30,
  }) async {
    lastQuery = query;
    return stubHits;
  }
}

Widget _wrapWithSize(Widget child, double width) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BibleSearchHit', () {
    test('formats passage ranges and resolves canonical book key', () {
      final hit = BibleSearchHit.fromJson({
        'id': 'w:10:11:1-5',
        'score': 0.92,
        'kind': 'passage',
        'bookNumber': 10,
        'bookName': '2 Samuel',
        'chapter': 11,
        'verse': 1,
        'endVerse': 5,
        'reference': '2 Samuel 11:1-5',
        'text': '1. At the return of the year...',
      });

      expect(hit.isPassage, isTrue);
      expect(hit.displayReference, '2 Samuel 11:1-5');
      expect(hit.canonicalBookKey, '2 Samuel');
    });
  });

  group('BibleSearchController', () {
    test('filters OT, NT, and Current Book scopes accurately', () async {
      final hits = [
        const BibleSearchHit(
          id: '26:37:1-5',
          score: 0.9,
          kind: 'passage',
          bookNumber: 26,
          bookName: 'Ezekiel',
          chapter: 37,
          verse: 1,
          endVerse: 5,
          reference: 'Ezekiel 37:1-5',
          text: 'The hand of Yahweh was on me...',
        ),
        const BibleSearchHit(
          id: '43:11:35',
          score: 0.85,
          kind: 'verse',
          bookNumber: 43,
          bookName: 'John',
          chapter: 11,
          verse: 35,
          reference: 'John 11:35',
          text: 'Jesus wept.',
        ),
      ];
      final service = _FakeBibleSearchService(hits);
      final controller = BibleSearchController(
        service: service,
        currentBook: 'John',
      );

      await controller.search('John 11:35');
      expect(service.lastQuery, 'John 11:35');
      expect(controller.state.directRef?.bookNumber, 43);
      expect(controller.state.filteredResults.length, 2);

      controller.setScope(BibleSearchScope.ot);
      expect(controller.state.filteredResults.map((e) => e.bookName), ['Ezekiel']);

      controller.setScope(BibleSearchScope.nt);
      expect(controller.state.filteredResults.map((e) => e.bookName), ['John']);

      controller.setScope(BibleSearchScope.book);
      expect(controller.state.filteredResults.map((e) => e.bookName), ['John']);
    });
  });

  group('BibleSearchScreen responsive layout', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders results without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = _FakeBibleSearchService(const [
          BibleSearchHit(
            id: '43:11:35',
            score: 1.67,
            kind: 'verse',
            bookNumber: 43,
            bookName: 'John',
            chapter: 11,
            verse: 35,
            reference: 'John 11:35',
            text: 'Jesus wept.',
          ),
          BibleSearchHit(
            id: 'w:43:11:34-38',
            score: 1.27,
            kind: 'passage',
            bookNumber: 43,
            bookName: 'John',
            chapter: 11,
            verse: 34,
            endVerse: 38,
            reference: 'John 11:34-38',
            text: '34. Where have you laid him? 35. Jesus wept.',
          ),
        ]);
        final controller = BibleSearchController(
          service: service,
          currentBook: 'John',
        );

        await tester.pumpWidget(
          _wrapWithSize(
            BibleSearchScreen(
              initialQuery: 'jesus wept',
              currentBook: 'John',
              controller: controller,
            ),
            width,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('John 11:35'), findsOneWidget);
        expect(find.text('John 11:34-38'), findsOneWidget);
        expect(find.text('Passage'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
