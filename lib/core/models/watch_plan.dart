import 'video.dart';

class WatchPlan {
  final String id;
  final String title;
  final String? description;
  final int targetMinutesPerDay;
  final List<Video> queuedVideos;
  final int completedVideosCount;
  final int streakDays;
  final DateTime createdAt;

  const WatchPlan({
    required this.id,
    required this.title,
    this.description,
    this.targetMinutesPerDay = 15,
    this.queuedVideos = const [],
    this.completedVideosCount = 0,
    this.streakDays = 0,
    required this.createdAt,
  });

  factory WatchPlan.fromJson(Map<String, dynamic> json) {
    var rawVideos = json['queuedVideos'] as List<dynamic>? ?? json['videos'] as List<dynamic>? ?? [];
    List<Video> parsedVideos = rawVideos
        .whereType<Map<String, dynamic>>()
        .map((v) => Video.fromJson(v))
        .toList();

    return WatchPlan(
      id: json['id'] ?? json['_id'] ?? '',
      title: json['title'] ?? 'Devotional Plan',
      description: json['description'],
      targetMinutesPerDay: json['targetMinutesPerDay'] ?? json['target_minutes'] ?? 15,
      queuedVideos: parsedVideos,
      completedVideosCount: json['completedVideosCount'] ?? json['completed_count'] ?? 0,
      streakDays: json['streakDays'] ?? json['streak_days'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'targetMinutesPerDay': targetMinutesPerDay,
      'queuedVideos': queuedVideos.map((v) => v.toJson()).toList(),
      'completedVideosCount': completedVideosCount,
      'streakDays': streakDays,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
