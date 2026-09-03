import 'package:sqflite/sqflite.dart';
import '../../models/verse_concept.dart';
import 'bible_study_repository.dart';
import 'bible_study_updater.dart';

class BibleStudyMobileService implements BibleStudyRepository {
  Database? _db;

  @override
  Future<void> initialize() async {
    final dbPath = await BibleStudyUpdater.getDatabasePath();
    if (dbPath != null) {
      _db = await openDatabase(dbPath, readOnly: true);
    }
  }

  @override
  Future<List<VerseConcept>> getConceptsForVerse(int book, int chapter, int verse) async {
    if (_db == null) {
      await initialize();
    }
    
    if (_db == null) return [];

    final result = await _db!.rawQuery('''
      SELECT 
        c.id as concept_id,
        c.canonical_name as concept_name,
        c.definition,
        c.biblical_meaning,
        c.historical_context,
        c.cultural_context,
        c.citations,
        l.lemma,
        l.language,
        l.original_word,
        l.strongs_id as strongs,
        l.transliteration,
        l.lexical_meaning
      FROM verse_occurrences vo
      JOIN surface_forms sf ON sf.id = vo.surface_form_id
      JOIN lemmas l ON l.id = sf.lemma_id
      JOIN concepts c ON c.id = l.concept_id
      WHERE vo.book = ? AND vo.chapter = ? AND vo.verse = ?
      GROUP BY c.id, l.lemma
    ''', [book, chapter, verse]);

    return result.map((row) {
      // Reconstruct the nested JSON structure expected by VerseConcept.fromJson
      return VerseConcept.fromJson({
        'concept_id': row['concept_id'],
        'concept_name': row['concept_name'],
        'definition': row['definition'],
        'biblical_meaning': row['biblical_meaning'],
        'historical_context': row['historical_context'],
        'cultural_context': row['cultural_context'],
        'citations': row['citations'] != null ? [row['citations']] : [], // Simplify for now, ideally parse JSON if citations is stringified JSON array in SQLite
        'original_language': {
          'lemma': row['lemma'],
          'language': row['language'],
          'original_word': row['original_word'],
          'strongs': row['strongs'],
          'transliteration': row['transliteration'],
          'lexical_meaning': row['lexical_meaning'],
        }
      });
    }).toList();
  }
}
