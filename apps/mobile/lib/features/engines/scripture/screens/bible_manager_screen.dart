import 'package:flutter/material.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Bible Translations',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF334155)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.offline_bolt_rounded,
                        color: Color(0xFFF59E0B),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Works 100% offline with instant verse switching',
                            style: TextStyle(
                              color: Colors.white70,
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
              const Text(
                'INSTALLED ON DEVICE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ...installedList.map((meta) => _buildInstalledItem(meta)),
              const SizedBox(height: 24),

              // 3. Available for Download Section Header & Search
              const Text(
                'AVAILABLE TO DOWNLOAD',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search languages or translations...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (availableList.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      'All available translations are installed!',
                      style: TextStyle(color: Colors.white54),
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

  Widget _buildInstalledItem(BibleVersionMeta meta) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF10B981),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${meta.language} • ${meta.sizeDisplay}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!meta.isDefaultBundled)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20),
              onPressed: () => _manager.removeVersion(meta.id),
            ),
        ],
      ),
    );
  }

  Widget _buildAvailableItem(BuildContext context, BibleVersionMeta meta) {
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${meta.language} • ${meta.sizeDisplay}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFF59E0B),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: startDownload,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
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
                backgroundColor: Colors.white10,
                color: const Color(0xFFF59E0B),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
