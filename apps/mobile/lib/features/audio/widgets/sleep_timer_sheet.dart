import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';

/// Adaptive bottom sheet for choosing a sleep timer duration (or turning it
/// off) in the full audio player.
Future<void> showSleepTimerSheet(BuildContext context) {
  final tokens = Theme.of(context).extension<AppTokens>();
  final theme = Theme.of(context);

  return showAdaptiveBottomSheet(
    context: context,
    backgroundColor: tokens?.background ?? theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sleep Timer',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens?.onSurface,
                    ),
              ),
              const SizedBox(height: 12),
              _SleepTimerOption(
                label: 'Off',
                onTap: () {
                  AudioPlayerController.instance.setSleepTimer(null);
                  Navigator.of(ctx).pop();
                },
              ),
              _SleepTimerOption(
                label: '15 minutes',
                onTap: () {
                  AudioPlayerController.instance.setSleepTimer(15);
                  Navigator.of(ctx).pop();
                },
              ),
              _SleepTimerOption(
                label: '30 minutes',
                onTap: () {
                  AudioPlayerController.instance.setSleepTimer(30);
                  Navigator.of(ctx).pop();
                },
              ),
              _SleepTimerOption(
                label: '45 minutes',
                onTap: () {
                  AudioPlayerController.instance.setSleepTimer(45);
                  Navigator.of(ctx).pop();
                },
              ),
              _SleepTimerOption(
                label: '60 minutes',
                onTap: () {
                  AudioPlayerController.instance.setSleepTimer(60);
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SleepTimerOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SleepTimerOption({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>();
    return ListTile(
      title: Text(label, style: TextStyle(color: tokens?.onSurface)),
      onTap: onTap,
    );
  }
}
