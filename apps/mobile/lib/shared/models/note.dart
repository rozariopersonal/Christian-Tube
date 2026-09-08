/// A user-authored note attached to a target (Bible verse, book line, article).
///
/// The model is intentionally generic so any reading surface (Bible reader,
/// book reader, article view) can reuse it. [feature] discriminates the owning
/// feature (`bible`, `book`, `article`) and [targetId] identifies the exact
/// anchor within that feature (e.g. `Genesis:1:3` for a Bible verse).
///
/// [contextText] optionally stores the anchored text (verse text, article
/// excerpt) so a notes list can show the target without resolving it.
class Note {
  final String id;
  final String feature;
  final String targetId;
  final String text;
  final String? contextText;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.feature,
    required this.targetId,
    required this.text,
    this.contextText,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isEmpty => text.trim().isEmpty;

  /// Canonical Bible anchor id: `Book:Chapter:Verse` (e.g. `Genesis:1:3`),
  /// matching the canonical `book:chapter:verse` key used by the reader.
  static String bibleTargetId(String book, int chapter, int verse) =>
      '$book:$chapter:$verse';

  Note copyWith({String? id, String? feature, String? targetId, String? text,
      String? Function()? contextText, DateTime? createdAt, DateTime? updatedAt}) {
    return Note(
      id: id ?? this.id,
      feature: feature ?? this.feature,
      targetId: targetId ?? this.targetId,
      text: text ?? this.text,
      contextText:
          contextText != null ? contextText() : this.contextText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'feature': feature,
        'targetId': targetId,
        'text': text,
        'contextText': contextText,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        feature: json['feature'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        contextText: json['contextText'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Column-shaped map for the SQLite `user_notes` table.
  Map<String, dynamic> toMap() => {
        'id': id,
        'feature': feature,
        'target_id': targetId,
        'text': text,
        'context_text': contextText,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as String,
        feature: map['feature'] as String,
        targetId: map['target_id'] as String,
        text: map['text'] as String? ?? '',
        contextText: map['context_text'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
