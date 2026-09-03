class VerseConcept {
  final String lemma;
  final String conceptId;
  final String conceptName;
  final String definition;
  final String biblicalMeaning;
  final String historicalContext;
  final String culturalContext;
  final List<String> citations;
  final OriginalLanguage? originalLanguage;

  VerseConcept({
    required this.lemma,
    required this.conceptId,
    required this.conceptName,
    required this.definition,
    required this.biblicalMeaning,
    required this.historicalContext,
    required this.culturalContext,
    required this.citations,
    this.originalLanguage,
  });

  factory VerseConcept.fromJson(Map<String, dynamic> json) {
    return VerseConcept(
      lemma: json['lemma'] as String? ?? '',
      conceptId: json['concept_id'] as String? ?? '',
      conceptName: json['concept_name'] as String? ?? '',
      definition: json['definition'] as String? ?? '',
      biblicalMeaning: json['biblical_meaning'] as String? ?? '',
      historicalContext: json['historical_context'] as String? ?? '',
      culturalContext: json['cultural_context'] as String? ?? '',
      citations: (json['citations'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      originalLanguage: json['original_language'] != null 
          ? OriginalLanguage.fromJson(json['original_language'] as Map<String, dynamic>) 
          : null,
    );
  }
}

class OriginalLanguage {
  final String lemma;
  final String transliteration;
  final String strongs;
  final String lexicalMeaning;

  OriginalLanguage({
    required this.lemma,
    required this.transliteration,
    required this.strongs,
    required this.lexicalMeaning,
  });

  factory OriginalLanguage.fromJson(Map<String, dynamic> json) {
    return OriginalLanguage(
      lemma: json['lemma'] as String? ?? '',
      transliteration: json['transliteration'] as String? ?? '',
      strongs: json['strongs'] as String? ?? '',
      lexicalMeaning: json['lexical_meaning'] as String? ?? '',
    );
  }
}
