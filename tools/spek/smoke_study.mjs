import { loadConfig } from './src/config.js';
import { BibleReader } from './src/bible_reader.js';
import { OllamaStudyClient } from './src/ollama_client.js';
import { StudyAnalyzer } from './src/study_analyzer.js';

const cfg = await loadConfig();
const reader = new BibleReader(cfg);
const llm = new OllamaStudyClient(cfg);
const anal = new StudyAnalyzer(llm);
const chap = await reader.getChapter(1, 1, 'ta_ovbsi');
console.log('chapter verses:', chap?.verses.length);
const t0 = Date.now();
const { output, inputTokens, outputTokens } = await anal.analyzeChapter(chap);
console.log('ELAPSED_S:', Math.round((Date.now() - t0) / 1000));
console.log('tokens:', inputTokens, 'in /', outputTokens, 'out');
console.log('terms:', output.terms?.length);
console.log('summary:', (output.chapter_summary || '').slice(0, 120));
for (const t of (output.terms || []).slice(0, 3)) {
  console.log('-', t.concept_name, '|', t.english_name, '|', t.lemma, '|', t.category, '|', t.certainty);
}