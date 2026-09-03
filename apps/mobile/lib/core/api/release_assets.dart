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

  /// Ordered candidate URLs for [relativePath]; jsDelivr CDN first (edge-
  /// cached globally), raw GitHub second as fallback.
  static List<String> urlsFor(String relativePath) => [
        'https://cdn.jsdelivr.net/gh/$_repo@$_branch/$relativePath',
        'https://raw.githubusercontent.com/$_repo/$_branch/$relativePath',
      ];
}