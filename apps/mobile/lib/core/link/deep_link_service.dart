import '../config/app_config.dart';

/// Builds canonical app deep links for every content type and normalizes
/// incoming shared URLs back to GoRouter locations.
///
/// Every outbound share should resolve its URL through this service so that
/// all content types share one URL contract. The consumer then passes the
/// result to [Share.share] (outbound) or to the router (inbound).
class DeepLinkService {
  DeepLinkService._();

  /// The web origin that hosts the app (used for shared links).
  static String get _origin => AppConfig.shareBaseUrl;

  // ---- Video / Short ----

  /// A shared link that opens the video player. Optionally seeks to [startSec].
  static String video(String videoId, {double? startSec}) {
    final id = Uri.encodeComponent(videoId);
    final base = '$_origin/watch/$id';
    return (startSec != null && startSec > 0)
        ? '$base?start=${startSec.toInt()}'
        : base;
  }

  /// A shared link that opens the shorts feed at a specific short.
  static String short(String shortId, {String? sourceVideoId, double? startSec}) {
    final target = sourceVideoId ?? shortId;
    return video(target, startSec: startSec);
  }

  // ---- Bible ----

  /// A shared link that opens the Bible reader at a passage.
  static String bible({
    String? version,
    String? book,
    int? chapter,
    int? verse,
  }) {
    final params = <String, String>{
      if (version != null && version.isNotEmpty) 'version': version,
      if (book != null && book.isNotEmpty) 'book': book,
      if (chapter != null) 'chapter': '$chapter',
      if (verse != null) 'verse': '$verse',
    };
    final qs = Uri(queryParameters: params).query;
    return '$_origin/bible${qs.isEmpty ? '' : '?$qs'}';
  }

  // ---- Books ----

  /// A shared link that opens the book reader.
  static String book(String bookId, {int? page}) {
    final id = Uri.encodeComponent(bookId);
    final base = '$_origin/books/$id';
    return (page != null && page > 0) ? '$base?page=$page' : base;
  }

  // ---- Articles ----

  /// A shared link that opens the article reader.
  static String article(String articleId, {String? lang}) {
    final id = Uri.encodeComponent(articleId);
    final base = '$_origin/article/$id';
    final langClean = lang?.trim();
    if (langClean == null || langClean.isEmpty || langClean == 'en') {
      return base;
    }
    return '$base?lang=$langClean';
  }

  // ---- Songs ----

  /// A shared link that opens the song reader.
  static String song(String songId) {
    return '$_origin/song/${Uri.encodeComponent(songId)}';
  }

  // ---- Audio ----

  /// A shared link that opens the audio series.
  static String audioSeries(String seriesId) {
    return '$_origin/audio/series/${Uri.encodeComponent(seriesId)}';
  }

  // ---- Inbound parsing ----

  /// Converts an incoming app URL (shared link) into a GoRouter location.
  ///
  /// Accepts absolute URLs (App Links / Universal Links) or plain paths. On
  /// web the route is already normalized by the router; this is mainly used to
  /// hand a cold/warm-start deep link from a native platform to GoRouter.
  static String toRouterLocation(String? url) {
    if (url == null || url.isEmpty) return '/feed';

    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return '/feed';
    }

    var path = uri.path;
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    // Rebuild the location with query params so start/bible/etc. survive.
    final qp = uri.queryParameters;
    return qp.isEmpty ? path : '$path?${Uri(queryParameters: qp).query}';
  }

  /// Extracts a YouTube video id from a fully-qualified YouTube url if the
  /// user shares a YouTube link directly (optionally for handling inbound
  /// YouTube URLs).
  static String? youtubeVideoId(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
        return null;
      }
      final id = uri.queryParameters['v'];
      if (id != null && id.isNotEmpty) return id;
      // youtu.be/VIDEO_ID style
      final segs = uri.pathSegments;
      if (segs.isNotEmpty) {
        final last = segs.last;
        if (last.isNotEmpty && last.length <= 16) return last;
      }
    } catch (_) {}
    return null;
  }
}
