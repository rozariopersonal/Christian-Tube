import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/screens/book_reader_screen.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'book_reader_font_size': 18.0,
      'book_reader_serif': false,
      'book_reader_theme_mode': 'light',
    });
  });

  testWidgets(
      'system back pops the book reader back to the previous page '
      '(never exits the app', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        extensions: const [AppTokens.light],
      ),
      navigatorKey: navKey,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => navKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const BookReaderScreen(bookId: 'missing_back_nav_book'),
                ),
              ),
              child: const Text('OPEN_READER'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('OPEN_READER'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue,
        reason: 'back must be intercepted by PopScope, not bubble to '
            'SystemNavigator.pop (app exit)');
    // Drive past the MaterialPageRoute exit transition (~300ms).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(BookReaderScreen), findsNothing);
    expect(find.text('OPEN_READER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}