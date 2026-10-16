import 'dart:convert';

/// Single scripture example sentence with Tamil text and English translation.
class GlossaryExample {
  final String sentenceTa;
  final String sentenceEn;

  const GlossaryExample({
    required this.sentenceTa,
    required this.sentenceEn,
  });

  factory GlossaryExample.fromMap(Map<String, dynamic> map) {
    return GlossaryExample(
      sentenceTa: map['sentence_ta'] as String? ?? '',
      sentenceEn: map['sentence_en'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'sentence_ta': sentenceTa,
        'sentence_en': sentenceEn,
      };
}

/// Comprehensive model representing a classical biblical glossary / lexicon entry.
///
/// Binds strictly to the real schema produced by `tool/build_taobvsi_glossary_deepseek.mjs`.
class GlossaryEntry {
  final String id;
  final String headword;
  final String transliteration;
  final String pos;
  final String posTa;
  final String category;
  final String glossEn;
  final String definitionTa;
  final String definitionEn;
  final String? originalLang;
  final String? originalLemma;
  final String? originalTranslit;
  final String? strongs;
  final List<String> modernEquivalents;
  final List<String> forms;
  final String notes;
  final List<GlossaryExample> examples;
  final List<String> seeAlso;
  final List<String> refs;
  final int occurrenceCount;

  const GlossaryEntry({
    required this.id,
    required this.headword,
    this.transliteration = '',
    required this.pos,
    required this.posTa,
    this.category = 'theological',
    required this.glossEn,
    required this.definitionTa,
    required this.definitionEn,
    this.originalLang,
    this.originalLemma,
    this.originalTranslit,
    this.strongs,
    this.modernEquivalents = const [],
    this.forms = const [],
    this.notes = '',
    this.examples = const [],
    this.seeAlso = const [],
    this.refs = const [],
    this.occurrenceCount = 0,
  });

  factory GlossaryEntry.fromMap(Map<String, dynamic> map) {
    List<String> parseStringList(dynamic raw) {
      if (raw == null) return const [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) return decoded.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      return const [];
    }

    List<GlossaryExample> parseExamples(dynamic raw) {
      if (raw == null) return const [];
      List<dynamic> list = [];
      if (raw is List) {
        list = raw;
      } else if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) list = decoded;
        } catch (_) {}
      }
      return list
          .whereType<Map>()
          .map((m) => GlossaryExample.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    return GlossaryEntry(
      id: map['id'] as String? ?? '',
      headword: map['headword'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      pos: map['pos'] as String? ?? '',
      posTa: map['pos_ta'] as String? ?? '',
      category: map['category'] as String? ?? 'theological',
      glossEn: map['gloss_en'] as String? ?? '',
      definitionTa: map['definition_ta'] as String? ?? '',
      definitionEn: map['definition_en'] as String? ?? '',
      originalLang: map['original_lang'] as String?,
      originalLemma: map['original_lemma'] as String?,
      originalTranslit: map['original_translit'] as String?,
      strongs: map['strongs'] as String?,
      modernEquivalents: parseStringList(map['modern_equivalents']),
      forms: parseStringList(map['forms']),
      notes: map['notes'] as String? ?? '',
      examples: parseExamples(map['examples']),
      seeAlso: parseStringList(map['see_also']),
      refs: parseStringList(map['refs']),
      occurrenceCount: map['occurrence_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'headword': headword,
        'transliteration': transliteration,
        'pos': pos,
        'pos_ta': posTa,
        'category': category,
        'gloss_en': glossEn,
        'definition_ta': definitionTa,
        'definition_en': definitionEn,
        'original_lang': originalLang,
        'original_lemma': originalLemma,
        'original_translit': originalTranslit,
        'strongs': strongs,
        'modern_equivalents': jsonEncode(modernEquivalents),
        'forms': jsonEncode(forms),
        'notes': notes,
        'examples': jsonEncode(examples.map((e) => e.toMap()).toList()),
        'see_also': jsonEncode(seeAlso),
        'refs': jsonEncode(refs),
        'occurrence_count': occurrenceCount,
      };
}
