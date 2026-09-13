import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../core/layout/adaptivity.dart';
import '../../audio/controllers/audio_player_controller.dart';

class FeedbackContextService {
  const FeedbackContextService();

  /// Formats human-friendly context badge from the current route and app state.
  String resolveScreenContext({
    required String routePath,
    Map<String, String>? queryParams,
    BuildContext? context,
  }) {
    final path = routePath.toLowerCase();

    if (path.startsWith('/bible')) {
      final version = queryParams?['version'] ?? 'Bible';
      final book = queryParams?['book'];
      final chapter = queryParams?['chapter'];
      final verse = queryParams?['verse'];
      final parts = <String>[];
      if (book != null && book.isNotEmpty) parts.add(book);
      if (chapter != null && chapter.isNotEmpty) {
        if (verse != null && verse.isNotEmpty) {
          parts.add('$chapter:$verse');
        } else {
          parts.add('Ch $chapter');
        }
      }
      final location = parts.isNotEmpty ? parts.join(' ') : 'Reader';
      return 'Bible • $location ($version)';
    }

    if (path.startsWith('/watch')) {
      final videoId = path.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => '');
      return videoId.isNotEmpty ? 'Video Player • ID: $videoId' : 'Video Player';
    }

    if (path.startsWith('/audio')) {
      final audioState = AudioPlayerController.instance.state;
      final track = audioState.currentTrack;
      if (audioState.hasTrack && track != null && track.title.isNotEmpty) {
        return 'Audio Player • ${track.title}';
      }
      return 'Audio Library';
    }

    if (path.startsWith('/shorts')) {
      return 'Shorts Feed';
    }

    if (path.startsWith('/words')) {
      return 'Words Micro-Feed';
    }

    if (path.startsWith('/books')) {
      return 'Book Reader';
    }

    if (path.startsWith('/songs')) {
      return 'Songs Library';
    }

    if (path.startsWith('/settings')) {
      return 'Settings & Customization';
    }

    if (path.startsWith('/profile')) {
      return 'Profile & Account';
    }

    if (path.startsWith('/search')) {
      return 'Search';
    }

    if (path.startsWith('/feed') || path == '/') {
      return 'Home Video Feed';
    }

    return 'General App';
  }

  /// Gathers safe, non-sensitive diagnostic info about the device & app.
  Map<String, dynamic> collectDiagnostics(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenClass = ScreenClass.of(context);

    return {
      'appName': AppConfig.appName,
      'appVersion': 'v${AppConfig.version}+${AppConfig.versionCode}',
      'instanceId': AppConfig.instanceId,
      'platform': defaultTargetPlatform.name,
      'isWeb': kIsWeb,
      'screenWidth': media?.size.width.round(),
      'screenHeight': media?.size.height.round(),
      'pixelRatio': media?.devicePixelRatio,
      'screenClass': screenClass.name,
      'isDark': isDark,
      'locale': Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en',
    };
  }
}
