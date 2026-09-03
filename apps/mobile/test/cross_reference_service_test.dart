import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/features/bible/services/cross_reference_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalBibleService.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('crossref_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
  });

  tearDown(() async {
    LocalBibleService.resetForTest();
    LocalBibleService.overrideDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('CrossReferenceService exposes on-demand status and clears cache', () async {
    final service = CrossReferenceService();
    expect(await service.isInstalled(), isTrue);
    expect(service.isDownloading, isFalse);
    expect(service.progress, 0.0);

    service.clearCache();
    await service.removeAll();
  });

  test('resolvePassages maps text for references', () async {
    final service = LocalBibleService();
    await service.initialize();

    await service.insertVerses('WEB', [
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 1,
        'verse': 1,
        'text': 'In the beginning was the Word.',
      },
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 1,
        'verse': 2,
        'text': 'The same was in the beginning with God.',
      },
    ]);

    final resolved = await service.resolvePassages(
      versionId: 'WEB',
      passages: [(43, 1, 1, null), (43, 1, 2, 3)],
    );

    expect(resolved['43_1_1'], 'In the beginning was the Word.');
    expect(resolved['43_1_2'], isNotNull);
  });
}
