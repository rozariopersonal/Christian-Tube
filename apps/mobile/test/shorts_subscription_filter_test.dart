import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shorts/services/shorts_subscription_filter.dart';

void main() {
  group('resolveSubscribedChannelIds', () {
    test('returns null (show all) when not signed in', () {
      expect(
        resolveSubscribedChannelIds(
          isAuthenticated: false,
          subscribedChannelIds: {'a'},
        ),
        isNull,
      );
    });

    test('returns null (show all) when the user has no subscriptions', () {
      expect(
        resolveSubscribedChannelIds(
          isAuthenticated: true,
          subscribedChannelIds: {},
        ),
        isNull,
      );
    });

    test('returns only the subscribed channel ids', () {
      final result = resolveSubscribedChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'en1', 'ta1'},
      );
      expect(result, {'en1', 'ta1'});
      expect(result, isNot(contains('other')));
    });

    test('never expands to non-subscribed channels', () {
      final result = resolveSubscribedChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: {'s1'},
      );
      expect(result, {'s1'});
      expect(result, isNot(contains('s2')));
    });

    test('returns an independent copy of the subscription set', () {
      final subscriptions = <String>{'a'};
      final result = resolveSubscribedChannelIds(
        isAuthenticated: true,
        subscribedChannelIds: subscriptions,
      );
      subscriptions.add('b');
      expect(result, {'a'});
    });
  });
}