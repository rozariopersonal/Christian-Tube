import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'deep_link_service.dart';

/// Listens for incoming deep links (Android App Links / web URLs) and routes
/// them into GoRouter.
///
/// On native platforms the app must explicitly consume the intent that opened
/// it (cold start) or the stream of new links (warm start). On the web the
/// router already resolves the browser URL natively, so this controller is a
/// no-op there to avoid conflicting double-navigation.
class DeepLinkController {
  DeepLinkController._();
  static final DeepLinkController instance = DeepLinkController._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GoRouter? _router;

  /// Begin listening. Called once after GoRouter is constructed.
  void attach(GoRouter router) {
    if (kIsWeb) return;
    _router = router;
    _sub ??= _appLinks.uriLinkStream.listen(_handle);
    _resolveInitial();
  }

  Future<void> _resolveInitial() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } catch (e) {
      debugPrint('DeepLink initial resolve error: $e');
    }
  }

  void _handle(Uri uri) {
    final location = DeepLinkService.toRouterLocation(uri.toString());
    final router = _router;
    if (router == null || location == '/feed') return;
    try {
      router.go(location);
    } catch (e) {
      debugPrint('DeepLink route error: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _router = null;
  }
}
