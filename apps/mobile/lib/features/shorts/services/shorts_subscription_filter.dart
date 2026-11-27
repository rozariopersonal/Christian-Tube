/// Resolves the channel ids whose shorts the community feed should show.
///
/// When subscribed to at least one channel (signed in or anonymous), the feed
/// is restricted to shorts from those subscribed channels only.
///
/// Returns `null` to mean "show all shorts" when there are no subscriptions yet.
Set<String>? resolveSubscribedChannelIds({
  required Set<String> subscribedChannelIds,
}) {
  if (subscribedChannelIds.isEmpty) return null;
  return Set<String>.of(subscribedChannelIds);
}