import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/services/audio_subscription_filter.dart';

AudioSeries _youtubeSeries(String id, String title) {
  return AudioSeries(
    id: id,
    title: title,
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: 5,
    category: 'YouTube',
    language: 'en',
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

  group('isSubscribedAudioSeries', () {
    test('matches a series whose title equals a subscribed channel name', () {
      final series = _youtubeSeries('cfc_india', 'CFC India');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelNames: const {'cfc india'},
          series: series,
        ),
        isTrue,
      );
    });

    test('matches by slugified id when the name differs in punctuation', () {
      // Worker stamps the id from slugify(channel_name); the subscribed name
      // may carry extra punctuation while the series title is the clean name.
      final series = _youtubeSeries('zac_poonen_sermons', 'Zac Poonen Sermons');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelNames: const {'Zac Poonen Sermons!'},
          series: series,
        ),
        isTrue,
      );
    });

    test('rejects channels the user is not subscribed to', () {
      final series = _youtubeSeries('alpha_channel', 'Alpha Channel');
      expect(
        isSubscribedAudioSeries(
          subscribedChannelNames: const {'Beta Channel'},
          series: series,
        ),
        isFalse,
      );
    });

    test('returns false for an empty subscription list', () {
      final series = _youtubeSeries('alpha_channel', 'Alpha Channel');
      expect(
        isSubscribedAudioSeries(subscribedChannelNames: const {}, series: series),
        isFalse,
      );
    });
  });
}