class ChannelRequest {
  final String? id;
  final String channelUrl;
  final String channelName;
  final String language;
  final String? notes;
  final String status;
  final DateTime createdAt;

  const ChannelRequest({
    this.id,
    required this.channelUrl,
    required this.channelName,
    required this.language,
    this.notes,
    this.status = 'pending',
    required this.createdAt,
  });

  factory ChannelRequest.fromJson(Map<String, dynamic> json) {
    return ChannelRequest(
      id: json['id'] ?? json['_id'],
      channelUrl: json['channelUrl'] ?? json['channel_url'] ?? '',
      channelName: json['channelName'] ?? json['channel_name'] ?? '',
      language: json['language'] ?? 'en',
      notes: json['notes'],
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channelUrl': channelUrl,
      'channelName': channelName,
      'language': language,
      'notes': notes,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
