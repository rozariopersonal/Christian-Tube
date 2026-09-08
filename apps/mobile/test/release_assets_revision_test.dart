import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api/release_assets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReleaseAssets.revision = '';
  });

  tearDown(() {
    ReleaseAssets.revision = '';
  });

  test('urlsFor returns jsDelivr first, raw GitHub fallback', () {
    final urls = ReleaseAssets.urlsFor('books/covers/the_way_of_wisdom.jpg');

    expect(urls.length, 2);
    expect(urls.first,
        startsWith('https://cdn.jsdelivr.net/gh/rozariopersonal/'));
    expect(urls.first, contains('Christian-Tube-Releases@main/'));
    expect(urls.last,
        startsWith('https://raw.githubusercontent.com/rozariopersonal/'));
  });

  test('urlsFor carry no cache-bust query when revision is empty', () {
    final urls = ReleaseAssets.urlsFor('books/covers/a.jpg');
    expect(urls.first.endsWith('books/covers/a.jpg'), isTrue);
    expect(urls.last.endsWith('books/covers/a.jpg'), isTrue);
    expect(urls.first.contains('?rv='), isFalse);
  });

  test('urlsFor cache-bust with ?rv= when a revision is set', () {
    ReleaseAssets.revision = '20ed2b66';

    final urls = ReleaseAssets.urlsFor('books/covers/a.jpg');
    expect(urls.first, endsWith('books/covers/a.jpg?rv=20ed2b66'));
    expect(urls.last, endsWith('books/covers/a.jpg?rv=20ed2b66'));
  });

  test('bookCoverUrl primary URL is revision-aware', () {
    ReleaseAssets.revision = '31f4cdc';

    final url = ReleaseAssets.urlsFor('books/covers/x.jpg').first;
    expect(url, contains('books/covers/x.jpg?rv=31f4cdc'));
  });
}