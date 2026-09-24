import '../models/audio_series.dart';

/// Whether [series] belongs to one of the user's subscribed channels.
///
/// Subscriptions are keyed by YouTube channel id (`Channel.id`). The backend
/// now stamps each channel-backed series with its `channelId` at sync time, so
/// the authoritative match is ID equality. A name-equality fallback is kept
/// only for series rows that predate the relational channelId field (e.g. a
/// SQLite mirror that has not re-synced yet); `slugifyChannelName` is no longer
/// the primary bridge.
bool isSubscribedAudioSeries({
  required Set<String> subscribedChannelIds,
  required Set<String> subscribedChannelNames,
  required AudioSeries series,
}) {
  if (subscribedChannelIds.isNotEmpty) {
    final channelId = series.channelId;
    if (channelId != null && channelId.isNotEmpty) {
      return subscribedChannelIds.contains(channelId);
    }
  }

  if (subscribedChannelNames.isEmpty) return false;

  final seriesTitle = series.title.trim().toLowerCase();
  if (seriesTitle.isEmpty) return false;

  final seriesName = series.channelName?.trim().toLowerCase() ?? seriesTitle;
  for (final rawName in subscribedChannelNames) {
    final name = rawName.trim();
    if (name.isEmpty) continue;
    if (name.toLowerCase() == seriesName) return true;
  }
  return false;
}

/// Slugifies a channel name exactly like the youtube-processor worker, which
/// keys audio series by `slugify(channel_name)`: lowercase, every run of
/// non-alphanumeric characters becomes a single underscore, and an empty
/// result falls back to `misc`.
///
/// Retained for legacy series rows and channel-name-keyed comparisons.
String slugifyChannelName(String name) {
  final cleaned = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'misc' : cleaned;
}