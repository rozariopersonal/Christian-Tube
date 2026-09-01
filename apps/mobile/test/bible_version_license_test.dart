import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/engines/scripture/models/bible_version_meta.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';

void main() {
  group('BibleVersionMeta Licensing & Attribution', () {
    test('serialization round-trip preserves all licensing fields', () {
      const meta = BibleVersionMeta(
        id: 'TEST_VER',
        name: 'Test Version',
        language: 'TestLang',
        languageCode: 'tl',
        sizeDisplay: '1.2 MB',
        description: 'Test translation description.',
        license: 'CC BY-SA 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
        copyrightHolder: 'Test Organization',
        attributionText: 'Test Attribution Notice © 2026',
        sourceUrl: 'https://example.com/bible',
      );

      final json = meta.toJson();
      final restored = BibleVersionMeta.fromJson(json);

      expect(restored.id, 'TEST_VER');
      expect(restored.license, 'CC BY-SA 4.0');
      expect(restored.licenseUrl, 'https://creativecommons.org/licenses/by-sa/4.0/');
      expect(restored.copyrightHolder, 'Test Organization');
      expect(restored.attributionText, 'Test Attribution Notice © 2026');
      expect(restored.sourceUrl, 'https://example.com/bible');
    });

    test('all catalog translations have valid license information', () {
      const catalog = BibleDownloadManager.catalog;
      expect(catalog, isNotEmpty);

      for (final version in catalog) {
        expect(version.id, isNotEmpty, reason: '${version.name} must have an ID');
        expect(version.license, isNotEmpty,
            reason: '${version.id} must have a non-empty license');
        expect(version.name, isNotEmpty);
        expect(version.language, isNotEmpty);
      }
    });

    test('Creative Commons IRV translations have explicit attribution notices', () {
      final irvs = ['MAL_IRV', 'TEL_IRV', 'KAN_IRV', 'HIN_IRV'];
      for (final id in irvs) {
        final meta = BibleDownloadManager.getMeta(id);
        expect(meta.license, contains('CC BY-SA 4.0'));
        expect(meta.copyrightHolder, isNotNull,
            reason: '$id must credit copyright holder under CC BY-SA');
        expect(meta.attributionText, isNotNull,
            reason: '$id must supply required legal attribution text');
      }
    });

    test('BSB (Berean Standard Bible) is cataloged with public domain license', () {
      final bsb = BibleDownloadManager.getMeta('BSB');
      expect(bsb.id, 'BSB');
      expect(bsb.language, 'English');
      expect(bsb.license, contains('Public Domain'));
      expect(bsb.copyrightHolder, isNotNull);
    });
  });
}
