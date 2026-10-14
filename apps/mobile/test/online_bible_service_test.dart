import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/engines/scripture/adapters/web_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/services/online_bible_service.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('OnlineBibleService Registry & Config Tests', () {
    test('isOnlineVersion detects all target English and Indian versions', () {
      final expectedOnline = [
        'NASB', 'NLT', 'MSG', 'NIV', 'AMP',
        'HIN_HCV', 'TAM_TCV', 'TEL_TCV', 'MAL_MCV', 'KAN_KCV',
        'BEN_BCV', 'MAR_MCV', 'PAN_PCV', 'URD_UCV', 'GUJ_IRV', 'ASM_IRV'
      ];

      for (final id in expectedOnline) {
        expect(OnlineBibleService.isOnlineVersion(id), isTrue,
            reason: '$id should be recognized as an online version');
        expect(OnlineBibleService.isOnlineVersion(id.toLowerCase()), isTrue,
            reason: '${id.toLowerCase()} should be case-insensitively recognized');
      }

      expect(OnlineBibleService.isOnlineVersion('KJV'), isFalse);
      expect(OnlineBibleService.isOnlineVersion('WEB'), isFalse);
      expect(OnlineBibleService.isOnlineVersion('UNKNOWN_VERSION'), isFalse);
    });

    test('onlineVersionIds includes NASB, NLT, MSG, NIV, AMP', () {
      final ids = OnlineBibleService.onlineVersionIds;
      expect(ids.contains('NASB'), isTrue);
      expect(ids.contains('NLT'), isTrue);
      expect(ids.contains('MSG'), isTrue);
      expect(ids.contains('NIV'), isTrue);
      expect(ids.contains('AMP'), isTrue);
      expect(ids.contains('TAM_TCV'), isTrue);
      expect(ids.contains('HIN_HCV'), isTrue);
    });

    test('NASB, NLT, and MSG configs have valid API configurations', () {
      final nasb = OnlineBibleService.getConfig('NASB');
      expect(nasb, isNotNull);
      expect(nasb!.provider, equals(OnlineProvider.apiBible));
      expect(nasb.apiBibleId, equals('b8ee27bcd1cae43a-01'));
      expect(nasb.youVersionId, equals(100));

      final nlt = OnlineBibleService.getConfig('NLT');
      expect(nlt, isNotNull);
      expect(nlt!.apiBibleId, equals('d6e14a625393b4da-01'));

      final msg = OnlineBibleService.getConfig('MSG');
      expect(msg, isNotNull);
      expect(msg!.apiBibleId, equals('6f11a7de016f942e-01'));

      final niv = OnlineBibleService.getConfig('NIV');
      expect(niv, isNotNull);
      expect(niv!.provider, equals(OnlineProvider.youVersion));
      expect(niv.youVersionId, equals(111));
    });
  });

  group('WebBibleDataAdapter Online Integration Tests', () {
    late WebBibleDataAdapter adapter;

    setUp(() async {
      adapter = WebBibleDataAdapter();
      await adapter.initialize();
    });

    tearDown(() async {
      await adapter.close();
    });

    test('getInstalledVersionIds includes online versions', () async {
      final ids = await adapter.getInstalledVersionIds();
      expect(ids.contains('NASB'), isTrue);
      expect(ids.contains('NLT'), isTrue);
      expect(ids.contains('MSG'), isTrue);
      expect(ids.contains('TAM_TCV'), isTrue);
      expect(ids.contains('HIN_HCV'), isTrue);
    });

    test('hasVerses returns true for online versions', () async {
      expect(await adapter.hasVerses('NASB'), isTrue);
      expect(await adapter.hasVerses('nlt'), isTrue);
      expect(await adapter.hasVerses('MSG'), isTrue);
      expect(await adapter.hasVerses('HIN_HCV'), isTrue);
    });

    test('getChapterVerseCounts provides fallback counts for online versions', () async {
      final counts = await adapter.getChapterVerseCounts('NASB');
      expect(counts, isNotEmpty);
      expect(counts.length, equals(66)); // 66 books of canon
    });
  });

  group('OnlineBibleService Live Chapter Fetching', () {
    test('fetches John 3 (book 43, ch 3) for NASB from API.Bible', () async {
      final verses = await OnlineBibleService.fetchLiveChapter('NASB', 43, 3);
      expect(verses, isNotEmpty);
      final v16 = verses.where((v) => v['verse'] == 16).firstOrNull;
      expect(v16, isNotNull);
      expect((v16!['text'] as String).toLowerCase(), contains('begotten son'));
    }, timeout: const Timeout(Duration(seconds: 25)));

    test('fetches Genesis 1 (book 1, ch 1) for MSG with span expansion', () async {
      final verses = await OnlineBibleService.fetchLiveChapter('MSG', 1, 1);
      expect(verses, isNotEmpty);
      expect(verses.length, greaterThan(15));
      final v1 = verses.where((v) => v['verse'] == 1).firstOrNull;
      expect(v1, isNotNull);
      expect((v1!['text'] as String).isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 25)));
  });
}
