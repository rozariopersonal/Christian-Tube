class FeedbackReport {
  final String text;
  final String screenContext;
  final String route;
  final Map<String, dynamic> diagnostics;
  final DateTime timestamp;

  FeedbackReport({
    required this.text,
    required this.screenContext,
    required this.route,
    required this.diagnostics,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'screenContext': screenContext,
      'route': route,
      'diagnostics': diagnostics,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory FeedbackReport.fromJson(Map<String, dynamic> json) {
    return FeedbackReport(
      text: json['text'] as String? ?? '',
      screenContext: json['screenContext'] as String? ?? 'General',
      route: json['route'] as String? ?? '/',
      diagnostics: (json['diagnostics'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
