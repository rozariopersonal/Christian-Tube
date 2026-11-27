import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/audio_processor_report_controller.dart';
import '../models/audio_processor_models.dart';
import '../services/admin_audio_background_coordinator.dart';

class AudioProcessorReportScreen extends StatefulWidget {
  final AudioProcessorReportController? controller;
  final bool? isAndroidOverride;

  const AudioProcessorReportScreen({
    super.key,
    this.controller,
    this.isAndroidOverride,
  });

  @override
  State<AudioProcessorReportScreen> createState() =>
      _AudioProcessorReportScreenState();
}

class _AudioProcessorReportScreenState
    extends State<AudioProcessorReportScreen> {
  late final AudioProcessorReportController _controller;
  late final bool _ownsController;

  bool get _isAndroid =>
      widget.isAndroidOverride ??
      AdminAudioBackgroundCoordinator.instance.isAndroidSupported;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AudioProcessorReportController();
    _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenClass = ScreenClass.of(context);
    final hPad = screenClass.isCompact ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: tokens.background,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Audio Processor',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
              ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            icon: Icon(Icons.refresh_rounded, color: tokens.onSurface),
            onPressed: _controller.load,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          return RefreshIndicator(
            onRefresh: _controller.load,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
              children: [
                MaxWidthBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.report.audioComAuthError != null) ...[
                        _AuthErrorBanner(
                          message: state.report.audioComAuthError!,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (state.errorMessage != null) ...[
                        _InlineErrorBanner(message: state.errorMessage!),
                        const SizedBox(height: 12),
                      ],
                      _LiveStatusCard(
                        state: state,
                        isAndroid: _isAndroid,
                        onRunNow: _controller.runNow,
                        onStop: _controller.stopRun,
                      ),
                      const SizedBox(height: 12),
                      _SummaryStatsSection(
                        report: state.report,
                        screenClass: screenClass,
                      ),
                      if (_isAndroid) ...[
                        const SizedBox(height: 12),
                        _SettingsCard(
                          settings: state.settings,
                          fcmConfigured: state.report.fcmConfigured,
                          fcmDeviceCount: state.report.fcmDeviceCount,
                          onChanged: _controller.updateSettings,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _ActivitySection(
                        state: state,
                        onFilterChanged: _controller.setFilter,
                        onTapItem: (item) => _showItemSheet(context, item),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showItemSheet(BuildContext context, AudioProcessorActivityItem item) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  item.title,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.channelName} • ${item.source.toUpperCase()} • ${item.status.toUpperCase()}',
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                ),
                if (item.error != null && item.error!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.error!,
                      style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (item.isFailed && _isAndroid)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _controller.runNow();
                        },
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Retry Now'),
                      ),
                    if (item.status != 'completed' && item.status != 'ignored')
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _controller.markIgnored(item.videoId);
                        },
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: const Text('Mark Ignored'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AuthErrorBanner extends StatelessWidget {
  final String message;
  const _AuthErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio.com Token Expired',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final String message;
  const _InlineErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onErrorContainer,
            ),
      ),
    );
  }
}

class _LiveStatusCard extends StatelessWidget {
  final AudioProcessorReportState state;
  final bool isAndroid;
  final VoidCallback onRunNow;
  final VoidCallback onStop;

  const _LiveStatusCard({
    required this.state,
    required this.isAndroid,
    required this.onRunNow,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final syncAt = state.report.lastDesktopSyncAt;
    final syncLabel = syncAt != null
        ? DateFormat('MMM d, h:mm a').format(syncAt.toLocal())
        : 'Not synced yet';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.running ? 'Processing Active' : 'Status: ${state.liveStatus}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last Desktop Neon Sync: $syncLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                  ),
                ],
              ),
              if (isAndroid)
                state.running
                    ? OutlinedButton.icon(
                        onPressed: onStop,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('Stop'),
                      )
                    : FilledButton.icon(
                        onPressed: onRunNow,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Check & Process Now'),
                      ),
            ],
          ),
          if (state.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.progressTotal > 0
                  ? state.progressDone / state.progressTotal
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              state.liveStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryStatsSection extends StatelessWidget {
  final AudioProcessorReport report;
  final ScreenClass screenClass;

  const _SummaryStatsSection({
    required this.report,
    required this.screenClass,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Pending (72h)', '${report.pendingCount}', Icons.hourglass_top_rounded),
      ('Completed (24h)', '${report.last24h.completed}', Icons.check_circle_outline),
      ('Failed (7d)', '${report.last7d.failed}', Icons.error_outline_rounded),
      ('Skipped (7d)', '${report.last7d.skipped}', Icons.skip_next_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final (label, value, icon) = stats[index];
            final tokens = context.tokens;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(icon, color: tokens.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: tokens.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.onSurfaceMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Last 7 days: ${report.last7d.mobileCompleted} via Mobile • ${report.last7d.desktopCompleted} via Desktop',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.tokens.onSurfaceMuted,
              ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final AudioProcessorSettings settings;
  final bool fcmConfigured;
  final int fcmDeviceCount;
  final ValueChanged<AudioProcessorSettings> onChanged;

  const _SettingsCard({
    required this.settings,
    required this.fcmConfigured,
    required this.fcmDeviceCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Background Settings',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Auto-Process without asking',
              style: TextStyle(color: tokens.onSurface, fontSize: 14),
            ),
            subtitle: Text(
              'Automatically convert new videos (last 72h) in background',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            ),
            value: settings.autoProcess,
            onChanged: (v) => onChanged(settings.copyWith(autoProcess: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Wi-Fi only',
              style: TextStyle(color: tokens.onSurface, fontSize: 14),
            ),
            value: settings.wifiOnly,
            onChanged: (v) => onChanged(settings.copyWith(wifiOnly: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Pause below 20% battery',
              style: TextStyle(color: tokens.onSurface, fontSize: 14),
            ),
            value: settings.pauseBelow20Battery,
            onChanged: (v) =>
                onChanged(settings.copyWith(pauseBelow20Battery: v)),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(
                avatar: Icon(
                  fcmConfigured
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 16,
                ),
                label: Text(
                  fcmConfigured
                      ? 'Push Ready ($fcmDeviceCount device${fcmDeviceCount == 1 ? '' : 's'})'
                      : 'Push Pending Firebase Key',
                ),
              ),
              const Chip(
                avatar: Icon(Icons.schedule_rounded, size: 16),
                label: Text('3h Catch-Up Active'),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  final AudioProcessorReportState state;
  final ValueChanged<ActivityFilter> onFilterChanged;
  final ValueChanged<AudioProcessorActivityItem> onTapItem;

  const _ActivitySection({
    required this.state,
    required this.onFilterChanged,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final items = state.filteredActivity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ActivityFilter.values.map((f) {
              final selected = state.filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    f.name[0].toUpperCase() + f.name.substring(1),
                  ),
                  selected: selected,
                  onSelected: (_) => onFilterChanged(f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        if (state.loading && items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Text(
              'No activity in this filter yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
            ),
          )
        else
          ...items.map((item) {
            final timeStr = DateFormat('MMM d, h:mm a').format(item.at.toLocal());
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: tokens.surfaceBorder),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onTapItem(item),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _StatusIcon(status: item.status),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: tokens.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.channelName} • ${item.source} • $timeStr',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: tokens.onSurfaceMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: tokens.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    switch (status) {
      case 'completed':
        return Icon(Icons.check_circle_rounded, color: cs.primary, size: 22);
      case 'failed':
      case 'dead':
        return Icon(Icons.error_rounded, color: cs.error, size: 22);
      default:
        return Icon(Icons.skip_next_rounded, color: tokens.onSurfaceMuted, size: 22);
    }
  }
}
