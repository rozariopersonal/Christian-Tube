/// Large data payloads (compiled bibles + topical feed list) are served from
/// the project's public releases repository so the app does not depend on the
/// Render-hosted backend for bulk downloads.
class ReleaseAssets {
  ReleaseAssets._();

  static const String owner = 'rozariopersonal';
  static const String repo = 'Christian-Tube-Releases';
  static const String branch = 'main';

  /// Ordered candidate URLs for [relativePath]; CDN first, raw GitHub second.
  static List<String> urlsFor(String relativePath) => [
        'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$relativePath',
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$relativePath',
      ];
}