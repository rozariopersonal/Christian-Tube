import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/adapters/web_book_data_adapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saving an existing highlight replaces its color on web', () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = WebBookDataAdapter();
    BookHighlight highlight(int color) => BookHighlight(
          id: 'one',
          bookId: 'book',
          chapterIndex: 1,
          pageNumber: 1,
          startChar: 0,
          endChar: 5,
          text: 'Grace',
          color: color,
          createdAt: '',
        );
    await adapter.saveHighlight(highlight(0));
    await adapter.saveHighlight(highlight(2));
    final saved = await adapter.getHighlightsForBook('book');
    expect(saved, hasLength(1));
    expect(saved.single.color, 2);
  });
}
