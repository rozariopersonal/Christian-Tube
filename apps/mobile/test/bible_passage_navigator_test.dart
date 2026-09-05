import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/bible/models/bible_reference.dart';
import 'package:mobile/features/bible/services/bible_passage_navigator.dart';

void main() {
  tearDown(() {
    BiblePassageNavigator.instance.reset();
  });

  group('BibleReference', () {
    test('maps book number to the canonical English book name', () {
      const ref = BibleReference(bookNumber: 43, chapter: 3, verse: 16);
      expect(ref.bookName, 'John');
      expect(ref.label, 'John 3:16');
    });

    test('builds a reference from a book name with spaces', () {
      final ref = BibleReference.fromBookName('Song of Solomon', 2, verse: 5);
      expect(ref.bookNumber, 22);
      expect(ref.label, 'Song of Solomon 2:5');
    });

    test('chapter-only label omits the verse', () {
      const ref = BibleReference(bookNumber: 1, chapter: 1);
      expect(ref.label, 'Genesis 1');
    });
  });

  group('BiblePassageNavigator', () {
    testWidgets('delivers the reference to an attached visible reader',
        (tester) async {
      BibleReference? received;
      await tester.pumpWidget(
        MaterialApp(
          home: _ProbeWidget(
            onBuild: (context) {
              BiblePassageNavigator.instance.attach(context, (ref) {
                received = ref;
              });
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      BiblePassageNavigator.instance.navigateTo(
        const BibleReference(bookNumber: 43, chapter: 3, verse: 16),
      );

      expect(received?.bookNumber, 43);
      expect(received?.chapter, 3);
      expect(received?.verse, 16);
    });

    testWidgets('routes to /bible when no reader is visible',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/feed',
        routes: [
          GoRoute(
            path: '/feed',
            builder: (_, __) => const Scaffold(body: Text('feed')),
          ),
          GoRoute(
            path: '/bible',
            builder: (_, state) {
              final qp = state.uri.queryParameters;
              return Scaffold(
                body: Text(
                    'bible:${qp['book']}:${qp['chapter']}:${qp['verse']}'),
              );
            },
          ),
        ],
      );
      BiblePassageNavigator.instance.init(router);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      BiblePassageNavigator.instance.navigateTo(
        const BibleReference(
          bookNumber: 43,
          chapter: 3,
          verse: 16,
          versionId: 'WEB',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('bible:John:3:16'), findsOneWidget);
    });
  });
}

class _ProbeWidget extends StatelessWidget {
  const _ProbeWidget({required this.onBuild});

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Scaffold(body: Text('probe'));
  }
}