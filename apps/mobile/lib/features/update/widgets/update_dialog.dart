import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

import '../controllers/update_download_controller.dart';
import '../services/release_highlights.dart';
import '../services/update_preferences.dart';
import '../update_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.updateData});
  final Map<String, dynamic> updateData;

  static Future<void> show(BuildContext context, Map<String, dynamic> data) {
    if (kIsWeb) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(updateData: data),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _download = UpdateDownloadController();

  @override
  void dispose() {
    _download.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = widget.updateData['latestVersion'] as String? ?? '';
    final current = widget.updateData['currentVersion'] as String? ?? '';
    final notes = releaseHighlights(
      widget.updateData['releaseNotes'] as String? ?? '',
    );
    final size = widget.updateData['sizeBytes'] as int? ?? 0;
    final url = widget.updateData['downloadUrl'] as String? ?? '';
    final releaseUrl = widget.updateData['releaseUrl'] as String? ?? '';
    return Dialog(
      backgroundColor: context.tokens.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: _download,
            builder: (context, _) {
              final state = _download.state;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.45,
                      ),
                      border: Border(
                        bottom: BorderSide(color: context.tokens.surfaceBorder),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.system_update_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Update Available!',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: context.tokens.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'A new version is ready when you are.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.tokens.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.downloading) ...[
                          Text(
                            state.retrying
                                ? 'Reconnecting…'
                                : 'Downloading update…',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: state.total > 0 && !state.retrying
                                ? (state.received / state.total).clamp(0.0, 1.0)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _download.cancel,
                            child: const Text('Cancel Download'),
                          ),
                        ] else if (state.path != null) ...[
                          Text(
                            'Download complete',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Continue in the Android installer.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () => UpdateService.launchApkInstaller(
                              state.path!,
                              url,
                            ),
                            child: const Text('Open installer'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: context.tokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: context.tokens.surfaceBorder,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AVAILABLE VERSION',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: context.tokens.onSurfaceMuted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      version,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (size > 0)
                                      Text(
                                        '·  ${(size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  context.tokens.onSurfaceMuted,
                                            ),
                                      ),
                                  ],
                                ),
                                if (current.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Installed: $current',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: context.tokens.onSurfaceMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            "What's New",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (notes.isEmpty)
                            Text(
                              'No release notes available.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: context.tokens.onSurfaceMuted,
                              ),
                            )
                          else
                            ...notes.map(
                              (note) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 3,
                                        right: 10,
                                      ),
                                      child: Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        note,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (releaseUrl.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed: () =>
                                    UpdateService.openInBrowser(releaseUrl),
                                child: const Text('View full release notes'),
                              ),
                            ),
                          if (state.error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              state.error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            if (url.isNotEmpty)
                              TextButton(
                                onPressed: () =>
                                    UpdateService.openInBrowser(url),
                                child: const Text('Download in browser'),
                              ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: url.isEmpty
                                ? null
                                : () => _download.start(url, size),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              state.error == null ? 'Update Now' : 'Retry',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 4),
                          OverflowBar(
                            alignment: MainAxisAlignment.spaceBetween,
                            overflowAlignment: OverflowBarAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Later'),
                              ),
                              TextButton(
                                onPressed: version.isEmpty
                                    ? null
                                    : () async {
                                        await UpdatePreferences.skip(version);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                child: const Text('Skip this version'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
