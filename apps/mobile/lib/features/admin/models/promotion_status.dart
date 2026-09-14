class PendingCommit {
  final String sha;
  final String message;
  final String author;

  const PendingCommit({
    required this.sha,
    required this.message,
    required this.author,
  });

  factory PendingCommit.fromJson(Map<String, dynamic> json) {
    return PendingCommit(
      sha: json['sha'] as String? ?? '',
      message: json['message'] as String? ?? '',
      author: json['author'] as String? ?? 'Unknown',
    );
  }
}

class PromotionStatus {
  final bool canPromote;
  final bool isBuilding;
  final int aheadCount;
  final List<PendingCommit> commits;
  final String latestProductionTag;
  final String? activeRunUrl;
  final String? message;

  const PromotionStatus({
    required this.canPromote,
    required this.isBuilding,
    required this.aheadCount,
    required this.commits,
    required this.latestProductionTag,
    this.activeRunUrl,
    this.message,
  });

  factory PromotionStatus.fromJson(Map<String, dynamic> json) {
    final rawCommits = json['commits'] as List<dynamic>? ?? [];
    return PromotionStatus(
      canPromote: json['canPromote'] == true,
      isBuilding: json['isBuilding'] == true,
      aheadCount: (json['aheadCount'] as num?)?.toInt() ?? 0,
      commits: rawCommits
          .map((c) => PendingCommit.fromJson(c as Map<String, dynamic>))
          .toList(),
      latestProductionTag: json['latestProductionTag'] as String? ?? 'Unknown',
      activeRunUrl: json['activeRunUrl'] as String?,
      message: json['message'] as String?,
    );
  }
}
