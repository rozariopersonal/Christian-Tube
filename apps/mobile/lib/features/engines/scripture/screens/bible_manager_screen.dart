import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/bible_version_meta.dart';
import '../services/bible_download_manager.dart';

class BibleManagerScreen extends StatefulWidget {
  const BibleManagerScreen({super.key});

  @override
  State<BibleManagerScreen> createState() => _BibleManagerScreenState();
}

class _BibleManagerScreenState extends State<BibleManagerScreen> {
  final BibleDownloadManager _manager = BibleDownloadManager();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _manager.refreshInstalledList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          'Bible Translations',
          style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AnimatedBuilder(
        animation: _manager,
        builder: (context, _) {
          final installedList = BibleDownloadManager.catalog
              .where((v) => _manager.isInstalled(v.id))
              .toList();

          final availableList = BibleDownloadManager.catalog
              .where((v) => !_manager.isInstalled(v.id))
              .where((v) =>
                  v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  v.language.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 1. Storage Summary Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tokens.surface, tokens.surfaceElevated],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.offline_bolt_rounded,
                        color: tokens.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${installedList.length} Translations Installed',
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Works 100% offline with instant verse switching',
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Installed Section
              Text(
                'INSTALLED ON DEVICE',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ...installedList.map((meta) => _buildInstalledItem(context, meta)),
              const SizedBox(height: 24),

              // 3. Available for Download Section Header & Search
              Text(
                'AVAILABLE TO DOWNLOAD',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(color: tokens.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search languages or translations...',
                  hintStyle: TextStyle(color: tokens.onSurfaceDisabled, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
                  filled: true,
                  fillColor: tokens.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (availableList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      'All available translations are installed!',
                      style: TextStyle(color: tokens.onSurfaceMuted),
                    ),
                  ),
                )
              else
                ...availableList
                    .map((meta) => _buildAvailableItem(context, meta)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInstalledItem(BuildContext context, BibleVersionMeta meta) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: tokens.accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.name,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${meta.language} • ${meta.sizeDisplay}',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!meta.isDefaultBundled)
            IconButton(
              icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
              onPressed: () => _manager.removeVersion(meta.id),
            ),
        ],
      ),
    );
  }

  Widget _buildAvailableItem(BuildContext context, BibleVersionMeta meta) {
    final tokens = context.tokens;
    final isDownloading = _manager.isDownloading(meta.id);
    final progress = _manager.getProgress(meta.id);

    Future<void> startDownload() async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await _manager.downloadVersion(meta);
      if (!ok && context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not download ${meta.name}. Check your connection and try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${meta.language} • ${meta.sizeDisplay}',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isDownloading)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: startDownload,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: tokens.surfaceBorder,
                color: tokens.accent,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
