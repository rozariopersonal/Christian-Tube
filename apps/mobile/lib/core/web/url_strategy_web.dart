import 'package:flutter_web_plugins/url_strategy.dart';

/// Web implementation: use clean path-based URLs (no '#') so shared links like
/// /watch/<id> resolve to real routes in the browser, Android App Links match
/// the same paths, and the OG function can serve preview meta.
void configureUrlStrategy() => usePathUrlStrategy();