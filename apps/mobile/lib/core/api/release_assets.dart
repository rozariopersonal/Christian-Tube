import 'package:mobile/core/config/app_config.dart';

/// Routes all data asset requests through the configured releases repository.
///
/// The repo is set via [AppConfig.releasesRepo] (loaded from
/// `assets/app_config.json`). Changing the repo there automatically updates
/// every data URL — no code changes required.
///
/// Prefer [GitHubDataService] for constructing asset URLs. Use this class
/// only to build the final candidate URL list from a relative path.
class ReleaseAssets {
  ReleaseAssets._();

  static const String _branch = 'main';

  /// Returns the owner/repo string from app config
  /// (e.g. `'rozariopersonal/Christian-Tube-Releases'`).
  static String get _repo => AppConfig.releasesRepo;

  /// Current dataset revision read from the top-level `manifest.json`
  /// (`revision` field). Bumping it on a data push changes every asset URL,
  /// which busts client (`CachedNetworkImage`) and CDN caches without an app
  /// release. Empty until [ReleaseRevision] resolves.
  static String revision = '';

  /// Query-string suffix that cache-busts asset URLs against the current
  /// dataset revision. Empty when no revision has been resolved yet.
  static String _revisionQuery() =>
      revision.isEmpty ? '' : '?rv=$revision';

  /// Ordered candidate URLs for [relativePath]; jsDelivr CDN first (edge-
  /// cached globally), raw GitHub second as fallback.
  static List<String> urlsFor(String relativePath) {
    final query = _revisionQuery();
    return [
      'https://cdn.jsdelivr.net/gh/$_repo@$_branch/$relativePath$query',
      'https://raw.githubusercontent.com/$_repo/$_branch/$relativePath$query',
    ];
  }
}