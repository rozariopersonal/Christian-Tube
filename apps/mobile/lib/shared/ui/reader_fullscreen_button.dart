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
        return Row(
          children: [
            Icon(Icons.fullscreen_rounded, color: tokens.onSurfaceMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auto fullscreen', style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.w600)),
                  Text('After inactivity while reading', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
                ],
              ),
            ),
            DropdownButton<int>(
              value: service.autoFullscreenSeconds,
              underline: const SizedBox.shrink(),
              dropdownColor: tokens.surface,
              style: TextStyle(color: tokens.onSurface),
              items: ReaderFullscreenService.supportedDelays.map((seconds) => DropdownMenuItem(
                value: seconds,
                child: Text(readerFullscreenDelayLabel(seconds)),
              )).toList(),
              onChanged: (seconds) {
                if (seconds != null) service.setAutoFullscreenSeconds(seconds);
              },
            ),
          ],
        );
      },
    );
  }
}
