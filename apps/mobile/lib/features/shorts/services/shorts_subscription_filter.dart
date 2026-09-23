/// Resolves the channel ids whose shorts the community feed should show.
///
/// When the user is signed in and subscribed to at least one channel, the feed
/// is restricted to shorts from those subscribed channels only.
///
/// Returns `null` to mean "show all shorts":
///  - the user is not signed in, or
///  - they have no subscriptions yet.
Set<String>? resolveSubscribedChannelIds({
  required bool isAuthenticated,
  required Set<String> subscribedChannelIds,
}) {
  if (!isAuthenticated || subscribedChannelIds.isEmpty) return null;
  return Set<String>.of(subscribedChannelIds);
}