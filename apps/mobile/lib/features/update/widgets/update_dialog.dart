import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/config/app_config.dart';
import '../update_service.dart';

class UpdateDialog extends StatefulWidget {
  final Map<String, dynamic> updateData;

  const UpdateDialog({super.key, required this.updateData});

  static Future<void> show(BuildContext context, Map<String, dynamic> updateData) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'UpdateDialog',
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => UpdateDialog(updateData: updateData),
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedValue = Curves.easeOutBack.transform(anim1.value) - 1.0;
        return Transform(
          transform: Matrix4.translationValues(0.0, curvedValue * -20, 0.0),
          child: Opacity(
            opacity: anim1.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _isCompleted = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadedApkPath;
  CancelToken? _cancelToken;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _isCompleted = false;
      _progress = 0.0;
      _errorMessage = null;
      _cancelToken = CancelToken();
    });

    final downloadUrl = widget.updateData['downloadUrl'] as String;

    UpdateService.downloadAndInstallApkWithProgress(
      downloadUrl: downloadUrl,
      cancelToken: _cancelToken,
      onProgress: (received, total) {
        if (mounted) {
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            if (total > 0) {
              _progress = received / total;
            }
          });
        }
      },
      onComplete: (savePath) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isCompleted = true;
            _progress = 1.0;
            _downloadedApkPath = savePath;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = err;
          });
        }
      },
    );
  }

  void _cancelDownload() {
    _cancelToken?.cancel('Cancelled by user');
    setState(() {
      _isDownloading = false;
      _progress = 0.0;
    });
  }

  void _triggerInstall() {
    if (_downloadedApkPath != null) {
      OpenFilex.open(
        _downloadedApkPath!,
        type: 'application/vnd.android.package-archive',
      );
    } else {
      final downloadUrl = widget.updateData['downloadUrl'] as String? ?? '';
      UpdateService.openInBrowser(downloadUrl);
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final latestVersion = widget.updateData['latestVersion'] ?? 'Latest';
    final currentVersion = widget.updateData['currentVersion'] ?? 'Current';
    final releaseNotes = widget.updateData['releaseNotes'] as String? ?? '';
    final sizeBytes = widget.updateData['sizeBytes'] as int? ?? 0;
    final downloadUrl = widget.updateData['downloadUrl'] as String? ?? '';

    final formattedSize = sizeBytes > 0 ? _formatBytes(sizeBytes) : 'Direct APK';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width.clamp(320.0, 420.0),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2129) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.6 : 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Banner with Gradient & App Icon
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF2C3E50),
                              const Color(0xFF1A1F2C),
                            ]
                          : [
                              const Color(0xFFEBF4FF),
                              const Color(0xFFF3E8FF),
                            ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Glowing Icon Container
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Image.asset(
                                'assets/logo.png',
                                width: 44,
                                height: 44,
                                errorBuilder: (ctx, _, __) => const Icon(
                                  Icons.rocket_launch_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Update Available!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Version comparison badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.12)
                                : Colors.black.withOpacity(0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentVersion,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                            Text(
                              latestVersion,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Content Body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isDownloading) ...[
                        // Downloading Progress State
                        _buildDownloadingView(isDark),
                      ] else if (_isCompleted) ...[
                        // Completed State
                        _buildCompletedView(downloadUrl),
                      ] else ...[
                        // Discovery / Ready State
                        _buildChangelogView(releaseNotes, formattedSize, isDark),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.15)
                                        : Colors.black.withOpacity(0.15),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Later',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB).withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _startDownload,
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Update Now',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              if (downloadUrl.isNotEmpty) {
                                UpdateService.openInBrowser(downloadUrl);
                              }
                            },
                            icon: const Icon(Icons.open_in_browser, size: 16),
                            label: const Text('Download APK in Browser (Direct Link)'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChangelogView(String releaseNotes, String formattedSize, bool isDark) {
    final cleanNotes = releaseNotes.trim().isNotEmpty
        ? releaseNotes.trim()
        : '• Performance improvements and faster video streaming\n• Enhanced Shorts feed gestures\n• Bug fixes and general stability updates';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                ),
                const SizedBox(width: 6),
                Text(
                  "What's New",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formattedSize,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: SingleChildScrollView(
            child: Text(
              cleanNotes,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingView(bool isDark) {
    final percentInt = (_progress * 100).toInt();

    return Column(
      children: [
        const SizedBox(height: 10),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 90,
              height: 90,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 7,
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percentInt%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Downloading',
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Downloading ${AppConfig.appName} Update...',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        if (_totalBytes > 0)
          Text(
            '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white10 : Colors.black12,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
          ),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: _cancelDownload,
          child: const Text(
            'Cancel Download',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView(String downloadUrl) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Download Complete!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Installer launched. If the system prompt did not appear, tap below to install or download directly via browser.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _triggerInstall,
            icon: const Icon(Icons.install_mobile, color: Colors.white),
            label: const Text(
              'Open / Install APK',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
