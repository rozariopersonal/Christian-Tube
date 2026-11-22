import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: _download,
            builder: (context, _) {
              final state = _download.state;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Update Available!',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Version $version${size > 0 ? ' · ${(size / (1024 * 1024)).toStringAsFixed(1)} MB' : ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (current.isNotEmpty)
                    Text(
                      'Installed: $current',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 20),
                  if (state.downloading) ...[
                    Text(
                      state.retrying ? 'Reconnecting…' : 'Downloading update…',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: state.total > 0 && !state.retrying
                          ? (state.received / state.total).clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _download.cancel,
                      child: const Text('Cancel Download'),
                    ),
                  ] else if (state.path != null) ...[
                    Text(
                      'Download complete. Continue in the Android installer.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          UpdateService.launchApkInstaller(state.path!, url),
                      child: const Text('Open installer'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ] else ...[
                    Text("What's New", style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (notes.isEmpty)
                      const Text('No release notes available.')
                    else
                      ...notes.map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: Text(note)),
                            ],
                          ),
                        ),
                      ),
                    if (releaseUrl.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            UpdateService.openInBrowser(releaseUrl),
                        child: const Text('View full release notes'),
                      ),
                    if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      if (url.isNotEmpty)
                        TextButton(
                          onPressed: () => UpdateService.openInBrowser(url),
                          child: const Text('Download in browser'),
                        ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: url.isEmpty
                            ? null
                            : () => _download.start(url, size),
                        child: Text(
                          state.error == null ? 'Update Now' : 'Retry',
                        ),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
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
                                  if (context.mounted) Navigator.pop(context);
                                },
                          child: const Text('Skip this version'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
