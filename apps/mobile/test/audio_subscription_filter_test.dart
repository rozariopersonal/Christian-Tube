import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/services/audio_subscription_filter.dart';

AudioSeries _youtubeSeries(
  String id,
  String title, {
  String? channelId,
}) {
  return AudioSeries(
    id: id,
    title: title,
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: 5,
    category: 'YouTube',
    language: 'en',
    channelId: channelId,
    channelName: title,
    tracks: const [],
  );
}

void main() {
  group('slugifyChannelName mirrors the youtube-processor worker', () {
    test('replaces non-alphanumeric runs with underscores and lowercases', () {
      expect(slugifyChannelName('Zac Poonen Sermons'), 'zac_poonen_sermons');
      expect(
          slugifyChannelName('English Channel (Live!)'), 'english_channel_live');
      expect(slugifyChannelName('  ***Special---Talks***  '), 'special_talks');
    });

    test('falls back to misc for empty or non-ASCII-only names', () {
      expect(slugifyChannelName(''), 'misc');
      expect(slugifyChannelName('   '), 'misc');
      expect(slugifyChannelName('தமிழ் பாடல்கள்'), 'misc');
    });
  });

  group('isSubscribedAudioSeries (ID-based)', () {
    test('matches series by its relational channelId', () {
      final series = _youtubeSeries(
        'chennai_cfc',
        'CHENNAI CFC',
        channelId: 'UCjOBTIP3cKg-F2MDsG8s5Og',
      );
      expect(
        isSubscribedAudioSeries(
          subscribedChannelIds: const {'UCjOBTIP3cKg-F2MDsG8s5Og'},
          subscribedChannelNames: const {},
          series: series,
        ),
        isTrue,
      );
    });

    test('rejects a series whose channelId is not subscribed', () {
      final series = _youtubeSeries(
        'chennai_cfc',
        'CHENNAI CFC',
        channelId: 'UCjOBTIP3cKg-F2MDsG8s5Og',
      );
      expect(
        isSubscribedAudioSeries(
          subscribedChannelIds: const {'UCL8wQnv6qB7rZtEYfY3vPtw'},
          subscribedChannelNames: const {},
          series: series,
        ),
        isFalse,
      );
    });

    test(
        'falls back to name matching for series without a relational channelId',
        () {
      // Legacy row still in the SQLite mirror before a re-sync.
      final series = _youtubeSeries('cfc_india', 'CFC India');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelIds: const {},
          subscribedChannelNames: const {'cfc india'},
          series: series,
        ),
        isTrue,
      );
    });

    test('rejects channels the user is not subscribed to (name path)', () {
      final series = _youtubeSeries('alpha_channel', 'Alpha Channel');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelIds: const {},
          subscribedChannelNames: const {'Beta Channel'},
          series: series,
        ),
        isFalse,
      );
    });

    test('returns false for empty subscription lists', () {
      final series = _youtubeSeries('alpha_channel', 'Alpha Channel');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelIds: const {},
          subscribedChannelNames: const {},
          series: series,
        ),
        isFalse,
      );
    });
  });
}