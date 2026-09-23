import '../models/audio_series.dart';

/// Slugifies a channel name exactly like the youtube-processor worker, which
/// keys audio series by `slugify(channel_name)`: lowercase, every run of
/// non-alphanumeric characters becomes a single underscore, and an empty
/// result falls back to `misc`.
String slugifyChannelName(String name) {
  final cleaned = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'misc' : cleaned;
}

/// Whether [series] belongs to one of the user's subscribed channels.
///
/// Channel subscriptions are keyed by YouTube channel id (`Channel.id`) while
/// audio series only carry the channel name (as `title` and a slugified `id`
/// stamped by the worker), so the two are bridged by name:
///  1. exact case-insensitive title equality (covers non-ASCII names, whose
///     slugs collapse into the worker's `misc` bucket), then
///  2. slug equality against the series id, mirroring the worker transform.
bool isSubscribedAudioSeries({
  required Set<String> subscribedChannelNames,
  required AudioSeries series,
}) {
  if (subscribedChannelNames.isEmpty) return false;

  final seriesTitle = series.title.trim().toLowerCase();
  if (seriesTitle.isEmpty) return false;

  for (final rawName in subscribedChannelNames) {
    final name = rawName.trim();
    if (name.isEmpty) continue;

    if (name.toLowerCase() == seriesTitle) return true;

    final slug = slugifyChannelName(name);
    if (slug == 'misc') continue;
    if (slug == series.id) return true;
  }
  return false;
}