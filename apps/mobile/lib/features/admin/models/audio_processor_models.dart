class PendingAudioVideo {
  final String id;
  final String title;
  final String channelName;
  final String channelId;
  final DateTime publishedAt;
  final String duration;
  final String thumbnail;
  final bool isSongChannel;

  const PendingAudioVideo({
    required this.id,
    required this.title,
    required this.channelName,
    required this.channelId,
    required this.publishedAt,
    required this.duration,
    required this.thumbnail,
    required this.isSongChannel,
  });

  factory PendingAudioVideo.fromJson(Map<String, dynamic> json) {
    return PendingAudioVideo(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      channelName: (json['channelName'] ?? 'Unknown').toString(),
      channelId: (json['channelId'] ?? '').toString(),
      publishedAt:
          DateTime.tryParse((json['publishedAt'] ?? '').toString()) ??
              DateTime.now().toUtc(),
      duration: (json['duration'] ?? '').toString(),
      thumbnail: (json['thumbnail'] ?? '').toString(),
      isSongChannel: json['isSongChannel'] == true,
    );
  }
}

class AudioProcessorWindowStats {
  final int completed;
  final int failed;
  final int skipped;
  final int mobileCompleted;
  final int desktopCompleted;

  const AudioProcessorWindowStats({
    this.completed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.mobileCompleted = 0,
    this.desktopCompleted = 0,
  });

  factory AudioProcessorWindowStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AudioProcessorWindowStats();
    return AudioProcessorWindowStats(
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      mobileCompleted: (json['mobileCompleted'] as num?)?.toInt() ?? 0,
      desktopCompleted: (json['desktopCompleted'] as num?)?.toInt() ?? 0,
    );
  }
}

class AudioProcessorActivityItem {
  final String videoId;
  final String title;
  final String channelName;
  final String status; // completed | failed | dead | short | ignored
  final String source; // mobile | desktop
  final String? adminEmail;
  final int? bytesUploaded;
  final int? durationSeconds;
  final String? error;
  final DateTime at;

  const AudioProcessorActivityItem({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.status,
    required this.source,
    this.adminEmail,
    this.bytesUploaded,
    this.durationSeconds,
    this.error,
    required this.at,
  });

  factory AudioProcessorActivityItem.fromJson(Map<String, dynamic> json) {
    return AudioProcessorActivityItem(
      videoId: (json['videoId'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      channelName: (json['channelName'] ?? 'Unknown').toString(),
      status: (json['status'] ?? 'failed').toString(),
      source: (json['source'] ?? 'mobile').toString(),
      adminEmail: json['adminEmail']?.toString(),
      bytesUploaded: (json['bytesUploaded'] as num?)?.toInt(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      error: json['error']?.toString(),
      at: DateTime.tryParse((json['at'] ?? '').toString()) ??
          DateTime.now().toUtc(),
    );
  }

  bool get isFailed => status == 'failed' || status == 'dead';
  bool get isSkipped => status == 'short' || status == 'ignored';
}

class AudioProcessorReport {
  final int pendingCount;
  final AudioProcessorWindowStats last24h;
  final AudioProcessorWindowStats last7d;
  final DateTime? lastDesktopSyncAt;
  final int desktopPushedCount;
  final String? audioComAuthError;
  final bool fcmConfigured;
  final int fcmDeviceCount;
  final List<AudioProcessorActivityItem> recentActivity;

  const AudioProcessorReport({
    this.pendingCount = 0,
    this.last24h = const AudioProcessorWindowStats(),
    this.last7d = const AudioProcessorWindowStats(),
    this.lastDesktopSyncAt,
    this.desktopPushedCount = 0,
    this.audioComAuthError,
    this.fcmConfigured = false,
    this.fcmDeviceCount = 0,
    this.recentActivity = const [],
  });

  factory AudioProcessorReport.fromJson(Map<String, dynamic> json) {
    final desktop = json['desktopSync'] as Map<String, dynamic>?;
    final authErr = json['audioComAuthError'] as Map<String, dynamic>?;
    final rawList = (json['recentActivity'] as List?) ?? const [];

    return AudioProcessorReport(
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      last24h: AudioProcessorWindowStats.fromJson(
        json['last24h'] as Map<String, dynamic>?,
      ),
      last7d: AudioProcessorWindowStats.fromJson(
        json['last7d'] as Map<String, dynamic>?,
      ),
      lastDesktopSyncAt: desktop?['lastDesktopSyncAt'] != null
          ? DateTime.tryParse(desktop!['lastDesktopSyncAt'].toString())
          : null,
      desktopPushedCount: (desktop?['pushedCount'] as num?)?.toInt() ?? 0,
      audioComAuthError: authErr?['error']?.toString(),
      fcmConfigured: json['fcmConfigured'] == true,
      fcmDeviceCount: (json['fcmDeviceCount'] as num?)?.toInt() ?? 0,
      recentActivity: rawList
          .whereType<Map<String, dynamic>>()
          .map(AudioProcessorActivityItem.fromJson)
          .toList(growable: false),
    );
  }
}

class AudioProcessorSettings {
  final bool autoProcess;
  final bool wifiOnly;
  final bool pauseBelow20Battery;

  const AudioProcessorSettings({
    this.autoProcess = false,
    this.wifiOnly = true,
    this.pauseBelow20Battery = true,
  });

  AudioProcessorSettings copyWith({
    bool? autoProcess,
    bool? wifiOnly,
    bool? pauseBelow20Battery,
  }) {
    return AudioProcessorSettings(
      autoProcess: autoProcess ?? this.autoProcess,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      pauseBelow20Battery: pauseBelow20Battery ?? this.pauseBelow20Battery,
    );
  }
}

class LocalAudioJobRecord {
  final String videoId;
  final String title;
  final String channelName;
  final String status;
  final String? uploadSessionId;
  final bool putSucceeded;
  final int? bytesUploaded;
  final int? durationSeconds;
  final String? error;
  final DateTime updatedAt;

  const LocalAudioJobRecord({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.status,
    this.uploadSessionId,
    this.putSucceeded = false,
    this.bytesUploaded,
    this.durationSeconds,
    this.error,
    required this.updatedAt,
  });

  Map<String, Object?> toDbRow() => {
        'videoId': videoId,
        'title': title,
        'channelName': channelName,
        'status': status,
        'uploadSessionId': uploadSessionId,
        'putSucceeded': putSucceeded ? 1 : 0,
        'bytesUploaded': bytesUploaded,
        'durationSeconds': durationSeconds,
        'error': error,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory LocalAudioJobRecord.fromDbRow(Map<String, Object?> row) {
    return LocalAudioJobRecord(
      videoId: (row['videoId'] ?? '').toString(),
      title: (row['title'] ?? 'Untitled').toString(),
      channelName: (row['channelName'] ?? 'Unknown').toString(),
      status: (row['status'] ?? 'pending').toString(),
      uploadSessionId: row['uploadSessionId']?.toString(),
      putSucceeded: (row['putSucceeded'] as int?) == 1,
      bytesUploaded: row['bytesUploaded'] as int?,
      durationSeconds: row['durationSeconds'] as int?,
      error: row['error']?.toString(),
      updatedAt:
          DateTime.tryParse((row['updatedAt'] ?? '').toString()) ??
              DateTime.now().toUtc(),
    );
  }
}
