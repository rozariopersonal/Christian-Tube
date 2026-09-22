import '../../../core/models/channel.dart';

/// Resolves the channel ids whose shorts the community feed should show when
/// the user is signed in and subscribed to channels.
///
/// The feed is personalized by language: the distinct languages spoken by the
/// channels the user subscribes to select EVERY channel in those languages (not
/// just the subscribed ones).
///
/// Returns `null` to mean "show all shorts":
///  - the user is not signed in, or
///  - they have no subscriptions, or
///  - the channel catalog has not been loaded yet (no language signal).
///
/// Subscribed channels are always included in the result set, so a subscribed
/// channel with an unknown/null language is not dropped from the user's feed.
Set<String>? resolveCandidateChannelIds({
  required bool isAuthenticated,
  required Set<String> subscribedChannelIds,
  required List<Channel> allChannels,
}) {
  if (!isAuthenticated || subscribedChannelIds.isEmpty) return null;
  if (allChannels.isEmpty) return null;

  final subscribedChannels =
      allChannels.where((c) => subscribedChannelIds.contains(c.id));

  final languages = subscribedChannels
      .map((c) => c.language?.trim().toLowerCase())
      .where((l) => l != null && l.isNotEmpty)
      .toSet();

  final matchedIds = allChannels
      .where((c) {
        final lang = c.language?.trim().toLowerCase();
        return lang != null && lang.isNotEmpty && languages.contains(lang);
      })
      .map((c) => c.id)
      .toSet();

  final result = matchedIds..addAll(subscribedChannelIds);
  return result.isEmpty ? null : result;
}