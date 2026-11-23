import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/update/services/update_preferences.dart';
import 'package:mobile/features/update/services/release_highlights.dart';

void main() {
  test('skip persists for the selected version only', () async {
    SharedPreferences.setMockInitialValues({});
    await UpdatePreferences.skip('v1.2.0-beta.1');
    expect(await UpdatePreferences.isSkipped('1.2.0-beta.1'), isTrue);
    expect(await UpdatePreferences.isSkipped('v1.2.0-beta.2'), isFalse);
    expect(await UpdatePreferences.isSkipped('v1.2.0'), isFalse);
  });

  test('extracts highlights without release download details', () {
    final notes = releaseHighlights('''### What's New
#### Features
- **bible**: Better navigation
- [Faster playback](https://example.com)
---
**Direct Download**: [app.apk](https://example.com/app.apk)
<img src="https://example.com/qr.png" />''');
    expect(notes, ['Better navigation', 'Faster playback']);
    expect(releaseHighlights('No notes available'), isEmpty);
  });
}
