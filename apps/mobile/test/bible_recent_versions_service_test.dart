import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/engines/scripture/services/bible_recent_versions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BibleRecentVersionsService', () {
    test('returns empty list initially', () async {
      final service = BibleRecentVersionsService();
      final recents = await service.getRecentVersions();
      expect(recents, isEmpty);
    });

    test('records versions in chronological order with most recent first', () async {
      final service = BibleRecentVersionsService();

      await service.recordRecentVersion('KJV');
      await service.recordRecentVersion('NIV');
      await service.recordRecentVersion('NASB');

      final recents = await service.getRecentVersions();
      expect(recents, ['NASB', 'NIV', 'KJV']);
    });

    test('de-duplicates case-insensitively and moves to top', () async {
      final service = BibleRecentVersionsService();

      await service.recordRecentVersion('KJV');
      await service.recordRecentVersion('NIV');
      await service.recordRecentVersion('kjv'); // duplicate with different case

      final recents = await service.getRecentVersions();
      expect(recents, ['kjv', 'NIV']);
    });

    test('caps at specified max items', () async {
      final service = BibleRecentVersionsService();

      for (int i = 1; i <= 15; i++) {
        await service.recordRecentVersion('V$i', maxRecents: 5);
      }

      final recents = await service.getRecentVersions();
      expect(recents.length, 5);
      expect(recents, ['V15', 'V14', 'V13', 'V12', 'V11']);
    });

    test('ignores empty or whitespace version IDs', () async {
      final service = BibleRecentVersionsService();

      await service.recordRecentVersion('NIV');
      await service.recordRecentVersion('   ');
      await service.recordRecentVersion('');

      final recents = await service.getRecentVersions();
      expect(recents, ['NIV']);
    });

    test('clears recent versions', () async {
      final service = BibleRecentVersionsService();

      await service.recordRecentVersion('NIV');
      await service.recordRecentVersion('NASB');
      await service.clearRecentVersions();

      final recents = await service.getRecentVersions();
      expect(recents, isEmpty);
    });
  });
}
