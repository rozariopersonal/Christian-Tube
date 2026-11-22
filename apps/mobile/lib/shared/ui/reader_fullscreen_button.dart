import 'package:flutter/material.dart';
import '../../core/services/reader_fullscreen_service.dart';
import '../../core/theme/app_tokens.dart';

class ReaderFullscreenButton extends StatelessWidget {
  const ReaderFullscreenButton({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: tokens.surface.withValues(alpha: 0.94),
            shape: const StadiumBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: 'Exit fullscreen reading',
              onPressed: onExit,
              icon: Icon(Icons.fullscreen_exit_rounded, color: tokens.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

String readerFullscreenDelayLabel(int seconds) => switch (seconds) {
      30 => '30 seconds',
      60 => '1 minute',
      120 => '2 minutes',
      _ => 'Off',
    };

/// Small shared preference control for the reading appearance sheet.
class ReaderFullscreenPreferenceControl extends StatelessWidget {
  const ReaderFullscreenPreferenceControl({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListenableBuilder(
      listenable: ReaderFullscreenService.instance,
      builder: (context, _) {
        final service = ReaderFullscreenService.instance;
        return ListTile(
          dense: true,
          minTileHeight: 36,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.timer_outlined, color: tokens.onSurfaceMuted),
          title: Text(
            'Auto fullscreen',
            style: TextStyle(color: tokens.onSurface),
          ),
          trailing: PopupMenuButton<int>(
            padding: EdgeInsets.zero,
            tooltip: 'Automatic fullscreen delay',
            color: tokens.surface,
            onSelected: service.setAutoFullscreenSeconds,
            itemBuilder: (context) => ReaderFullscreenService.supportedDelays
                .map((seconds) => PopupMenuItem(
                      value: seconds,
                      child: Text(readerFullscreenDelayLabel(seconds)),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                readerFullscreenDelayLabel(service.autoFullscreenSeconds),
                style: TextStyle(color: tokens.onSurface),
              ),
            ),
          ),
        );
      },
    );
  }
}
