import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/features/shorts/services/shorts_language_filter.dart';

Channel _channel(String id, {String? language}) => Channel(
      id: id,
      title: 'T$id',
      avatarUrl: '',
      language: language,
    );

void main() {
  group('resolveCandidateChannelIds', () {
    test('returns null (show all) when not signed in', () {
      expect(
        resolveCandidateChannelIds(
          isAuthenticated: false,
          subscribedChannelIds: {'a'},
          allChannels: [_channel('a', language: 'English')],
        ),
        isNull,
      );
    });

    test('returns null (show all) when the user has no subscriptions', () {
      expect(
        resolveCandidateChannelIds(
          isAuthenticated: true,
          subscribedChannelIds: {},
          allChannels: [_channel('a', language: 'English')],
        ),
        isNull,
      );
    });

    test('returns null (show all) when the catalog is not loaded', () {
      expect(
        resolveCandidateChannelIds(
          isAuthenticated: true,
          subscribedChannelIds: {'a'},
          allChannels: const [],
        ),
        isNull,
      );
    });

    test('matches every channel in the subscribed languages', () {
      final channels = [
        _channel('en1', language: 'English'),
        _channel('en2', language: 'English'),
        _channel('ta1', language: 'Tamil'),
        _channel('hi1', language: 'Hindi'),
      ];
      final result = resolveCandidateChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'en1'},
        allChannels: channels,
      )!;
      expect(result, containsAll({'en1', 'en2'}));
      expect(result, isNot(contains('ta1')));
      expect(result, isNot(contains('hi1')));
    });

    test('keeps subscribed channels even with an unknown language', () {
      final channels = [
        _channel('sub'),
        _channel('other', language: 'English'),
      ];
      final result = resolveCandidateChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'sub'},
        allChannels: channels,
      )!;
      expect(result, contains('sub'));
    });

    test('language matching is case and whitespace insensitive', () {
      final channels = [
        _channel('s1', language: '  English  '),
        _channel('s2', language: 'enGlIsH'),
        _channel('s3', language: 'FRENCH'),
      ];
      final result = resolveCandidateChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'s1'},
        allChannels: channels,
      )!;
      expect(result, containsAll({'s1', 's2'}));
      expect(result, isNot(contains('s3')));
    });

    test('unions the languages of every subscribed channel', () {
      final channels = [
        _channel('taSub', language: 'Tamil'),
        _channel('teSub', language: 'Telugu'),
        _channel('taOther', language: 'Tamil'),
        _channel('enOther', language: 'English'),
      ];
      final result = resolveCandidateChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'taSub', 'teSub'},
        allChannels: channels,
      )!;
      expect(result, containsAll({'taSub', 'teSub', 'taOther'}));
      expect(result, isNot(contains('enOther')));
    });

    test('falls back to subscribed channels absent from the catalog', () {
      final channels = [_channel('ta1', language: 'Tamil')];
      final result = resolveCandidateChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'en1'},
        allChannels: channels,
      )!;
      // No language signal, but the subscribed channel is never dropped.
      expect(result, {'en1'});
    });
  });

  group('Channel.language', () {
    test('fromJson reads the language the backend sends', () {
      final channel = Channel.fromJson({
        'id': 'x',
        'title': 'X',
        'avatarUrl': 'a',
        'language': 'Tamil',
      });
      expect(channel.language, 'Tamil');
    });

    test('fromJson tolerates a missing language', () {
      final channel = Channel.fromJson({
        'id': 'x',
        'title': 'X',
        'avatarUrl': 'a',
      });
      expect(channel.language, isNull);
    });

    test('toJson round-trips the language', () {
      final channel = _channel('x', language: 'English');
      final json = channel.toJson();
      expect(json['language'], 'English');
      expect(Channel.fromJson(json).language, 'English');
    });
  });
}