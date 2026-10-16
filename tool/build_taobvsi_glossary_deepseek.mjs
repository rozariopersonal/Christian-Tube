#!/usr/bin/env node
/**
 * tool/build_taobvsi_glossary_deepseek.mjs
 * 
 * Exhaustive Biblical Lexicon & Glossary builder for the Tamil Old Version Bible (TAOVBSI)
 * powered by DeepSeek-V3 (deepseek-chat).
 * 
 * Features:
 * - Extracts every meaningful noun, verb, adjective, and adverb with classical theological definitions.
 * - Id is the clean ASCII romanized transliteration (e.g. "karttar").
 * - Gathers inflected surface forms under canonical Tamil lemmas.
 * - Bilingual: Classical reverent TAOVBSI Tamil + scholarly English gloss and definition.
 * - Original languages: Hebrew/Aramaic (OT) and Koine Greek (NT) lemmas and Strong's numbers.
 * - Modern equivalents: Bridges 19th-century TAOVBSI archaic terms to contemporary vernacular.
 * - Smart Chunking: Chapters with > 50 verses are automatically split to guarantee zero 8k token truncation.
 * - Resumable & Fault-tolerant: Per-chapter JSON caching in .cache/glossary_deepseek/chapters/
 * - Local Deduplication & Mathematical Verse Mapping in --compile pass.
 * - Produces high-performance SQLite database with FTS5 search (taobvsi_glossary.sqlite).
 * 
 * Usage:
 *   node tool/build_taobvsi_glossary_deepseek.mjs --test
 *   node tool/build_taobvsi_glossary_deepseek.mjs --status
 *   node tool/build_taobvsi_glossary_deepseek.mjs --book 1
 *   node tool/build_taobvsi_glossary_deepseek.mjs --all --concurrency 5
 *   node tool/build_taobvsi_glossary_deepseek.mjs --compile
 */

import fs from 'fs';
import path from 'path';
import https from 'https';
import zlib from 'zlib';
import { fileURLToPath } from 'url';
import { DatabaseSync } from 'node:sqlite';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
function resolveApiKey() {
  if (process.env.DEEPSEEK_API_KEY) return process.env.DEEPSEEK_API_KEY;
  const envFile = path.join(ROOT, 'envs', 'common.env');
  if (fs.existsSync(envFile)) {
    const lines = fs.readFileSync(envFile, 'utf8').split('\n');
    for (const line of lines) {
      const match = line.match(/^DEEPSEEK_API_KEY\s*=\s*(.+)$/);
      if (match) return match[1].trim();
    }
  }
  return '';
}

const API_KEY = resolveApiKey();
const API_URL = 'https://api.deepseek.com/chat/completions';
const MODEL_ID = 'deepseek-chat';

const BIBLE_DIR = path.join(ROOT, 'releases', 'bibles', 'taobvsi');
const BOOKS_FILE = path.join(BIBLE_DIR, 'books.json');

const CACHE_DIR = path.join(ROOT, '.cache', 'glossary_deepseek');
const CHAPTERS_CACHE_DIR = path.join(CACHE_DIR, 'chapters');
const STATUS_FILE = path.join(CACHE_DIR, 'status.json');

const RELEASES_STUDY_DIR = path.join(ROOT, 'releases', 'study', 'taobvsi');
const SQLITE_OUT = path.join(RELEASES_STUDY_DIR, 'taobvsi_glossary.sqlite');
const SQLITE_GZ_OUT = path.join(RELEASES_STUDY_DIR, 'taobvsi_glossary.sqlite.gz');

// Ensure cache directories exist
fs.mkdirSync(CHAPTERS_CACHE_DIR, { recursive: true });
fs.mkdirSync(RELEASES_STUDY_DIR, { recursive: true });

// Standard OSIS book codes
const OSIS_BOOK_CODES = {
  1: 'GEN', 2: 'EXO', 3: 'LEV', 4: 'NUM', 5: 'DEU', 6: 'JOS', 7: 'JDG', 8: 'RUT',
  9: '1SA', 10: '2SA', 11: '1KI', 12: '2KI', 13: '1CH', 14: '2CH', 15: 'EZR', 16: 'NEH',
  17: 'EST', 18: 'JOB', 19: 'PSA', 20: 'PRO', 21: 'ECC', 22: 'SNG', 23: 'ISA', 24: 'JER',
  25: 'LAM', 26: 'EZK', 27: 'DAN', 28: 'HOS', 29: 'JOL', 30: 'AMO', 31: 'OBA', 32: 'JON',
  33: 'MIC', 34: 'NAM', 35: 'HAB', 36: 'ZEP', 37: 'HAG', 38: 'ZEC', 39: 'MAL', 40: 'MAT',
  41: 'MRK', 42: 'LUK', 43: 'JHN', 44: 'ACT', 45: 'ROM', 46: '1CO', 47: '2CO', 48: 'GAL',
  49: 'EPH', 50: 'PHP', 51: 'COL', 52: '1TH', 53: '2TH', 54: '1TI', 55: '2TI', 56: 'TIT',
  57: 'PHM', 58: 'HEB', 59: 'JAS', 60: '1PE', 61: '2PE', 62: '1JN', 63: '2JN', 64: '3JN',
  65: 'JUD', 66: 'REV'
};

// ---------------------------------------------------------------------------
// DeepSeek API Client
// ---------------------------------------------------------------------------
function callDeepSeekOnce(messages, maxTokens = 8192) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      model: MODEL_ID,
      messages,
      max_tokens: maxTokens,
      temperature: 0.1,
      response_format: { type: 'json_object' }
    });

    const req = https.request(API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${API_KEY}`,
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 180000 // 3 min timeout
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (res.statusCode !== 200) {
            return reject(new Error(`API Error ${res.statusCode}: ${JSON.stringify(parsed)}`));
          }
          resolve(parsed);
        } catch (e) {
          reject(new Error(`Failed to parse response: ${body.slice(0, 500)}`));
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timed out after 180s'));
    });
    req.write(postData);
    req.end();
  });
}

export async function callDeepSeek(messages, maxTokens = 8192, retries = 4) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await callDeepSeekOnce(messages, maxTokens);
    } catch (err) {
      console.warn(`[DeepSeek Attempt ${attempt}/${retries} failed: ${err.message}]`);
      if (attempt === retries) throw err;
      const delay = Math.min(2000 * Math.pow(1.5, attempt), 10000);
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

// ---------------------------------------------------------------------------
// Prompt Construction
// ---------------------------------------------------------------------------
function buildSystemPrompt(isOT) {
  const origLangDesc = isOT
    ? `Give the Hebrew lemma and Strong's number only if you are confident. Otherwise set "original" to null. A wrong number is worse than none.`
    : `Give the Greek lemma and Strong's number only if you are confident. Otherwise set "original" to null. A wrong number is worse than none.`;
  const origExample = isOT
    ? `{"lang":"he","lemma":"...","strongs":"H####"} or null`
    : `{"lang":"grc","lemma":"...","strongs":"G####"} or null`;

  return `You are a lexicographer of classical ecclesiastical Tamil, working on the TAOVBSI (பரிசுத்த வேதாகமம், Tamil Old Version, BSI). You will receive a small block of verses. Extract a glossary of meaningful content words from ONLY those verses and reply with a single JSON object.

CRITICAL DEDUPLICATION RULE:
- If a list titled "CRITICAL EXCLUSION LIST (ALREADY EXTRACTED WORDS)" is provided in the user prompt, those words have ALREADY been fully cataloged and indexed from previous passages.
- Under NO circumstances should any word in that list (or any inflected form or lemma variant of those words) appear in your "entries" array.
- Every single entry in your output MUST be a brand-new content word not present in the exclusion list.
- Re-extracting an excluded word violates the lexicographical contract.

WHAT TO EXTRACT
- Nouns, verbs, adjectives, adverbs that carry theological, ethical, emotional, historical, ceremonial or cultural weight.
- Skip pronouns, conjunctions, particles, auxiliary verbs, and everyday filler words (என், உம், அவர், என்று, ஆனால், ஆகையால், அப்பொழுது, இதோ).
- Group inflected forms under one headword. Do NOT merge words that are different lexemes, even if related (வசனம், வார்த்தை, வாக்கு are three separate entries).

LEMMA CONVENTIONS
- Nouns: nominative singular (கற்பனை, not கற்பனைகளை).
- Verbs: bare stem as used in a dictionary (கைக்கொள், தியானி, தேடு). Do not use the -தல் verbal noun.
- Compound verbs such as வெட்கப்பட்டுப்போ: lemma is the full compound, or use the noun (வெட்கம்). Pick one and do not create both.
- Adjectives and adverbs: base form.

PROPER NAMES & BIBLICAL PERSONS
- When extracting names of persons (category: "person"):
  Provide disambiguating biographical facts in both definitions: state who they are, their parent / lineage (e.g. "son of X"), spouse/family, tribe, official role, and key biblical event or distinctive association that uniquely identifies them. Never give a generic or vague definition like "a person in the Bible".
  For persons, "examples" should be [] unless a general contextual usage applies.

FORMS
- "forms" must be copied character for character from the supplied verse text. Never construct, normalise or correct a form. If you are unsure a form appears, leave it out.
- Do not output verse references. They are computed by software afterwards.

TAOVBSI REGISTER (applies to every Tamil string you write)
- Dignified Protestant TAOVBSI Tamil. Use வேதாகமம், தேவன், கர்த்தர்.
- Never use Catholic or ecumenical terms: விவிலியம், மறைநூல், இறைவன், திருச்சட்டம், ஆண்டவர் (as a name of God), இறைவாக்கு.
- "modern_equivalents" must be plain everyday Tamil synonyms that are not on that forbidden list. If none fits, return [].

EXAMPLES (2 COMPLETELY DIFFERENT CONTEXTS)
- For every vocabulary word (nouns, verbs, adjectives, adverbs):
  Provide an array of exactly 2 objects in "examples": [{"sentence_ta": "...", "sentence_en": "..."}, {"sentence_ta": "...", "sentence_en": "..."}].
- The 2 examples MUST be completely different in context and setting from the verse currently being analyzed (e.g. if the word appears in a physical context in the verse, give examples of spiritual, covenantal, or devotional usage elsewhere in Scripture).
- Both sentences must use classical TAOVBSI Protestant Tamil with an English translation.
- For proper names of persons where example sentences do not apply, return [].

NOTES FIELD GUIDELINES
- Provide high-value biblical study context, or leave as empty string "" if none applies:
  1. Etymology: Literal Hebrew/Greek meaning of proper names (e.g. Cain = "acquired", Jacob = "heel-catcher", Abel = "breath/vanity").
  2. Disambiguation: Distinguish multiple people or places sharing the same name (e.g. "Do not confuse with Enoch son of Jared in Gen 5").
  3. Typology: Foreshadowing of Christ, New Testament fulfillment, or covenantal connection.
  4. Weights & Measures: Convert ancient biblical units to modern metric/imperial equivalents (e.g. cubit = 45 cm / 18 inches).
  5. Archaic Tamil: Clarify archaic 19th-century TAOVBSI ecclesiastical idioms.

ORIGINAL LANGUAGE
- "original" is optional. ${origLangDesc}

FIELDS
Each entry has exactly these keys:
- id: ascii snake_case slug, unique in your reply
- headword: Tamil lemma
- transliteration: Latin transliteration
- pos: one of noun, verb, adjective, adverb
- pos_ta: பெயர்ச்சொல் | வினைச்சொல் | பெயரடை | வினையடை (matching pos)
- category: one of divine_name, theology, covenant, person, place, body, attribute, emotion, action, time, nature, sacrifice, other
- forms: array of exact surface forms from the text
- gloss_en: short English gloss
- definition_ta: one or two sentences of classical Tamil (for persons: state who, parentage/lineage, role, and unique distinguishing details)
- definition_en: one or two sentences of English (for persons: state who, parentage/lineage, role, and unique distinguishing details)
- examples: array of 2 objects [{"sentence_ta": "...", "sentence_en": "..."}, {"sentence_ta": "...", "sentence_en": "..."}] with completely different contexts from the passage; or [] for persons
- original: ${origExample}
- modern_equivalents: array of Tamil strings
- see_also: array of ids of other entries in THIS reply, or []
- notes: string (etymology, disambiguation, typology, weights/measures, or archaic Tamil; or "")

OUTPUT RULES
- Output one valid JSON object and nothing else: {"entries":[ ... ]}. No markdown fences, no commentary, no trailing commas.
- Return 12 to 15 of the most significant, high-value distinct vocabulary words from this passage that are NOT in the exclusion list. Prioritize rich theological, ceremonial, and distinct narrative terms over trivial everyday words. Do NOT output more than 15 entries so the complete JSON response finishes cleanly without truncation.

EXAMPLE OF THE FORMAT (illustrative only, do not copy its content)
{"entries":[{"id":"kirubai","headword":"கிருபை","transliteration":"kirubai","pos":"noun","pos_ta":"பெயர்ச்சொல்","category":"theology","forms":["கிருபை","கிருபையினால்"],"gloss_en":"grace","definition_ta":"தகுதியற்ற மனிதனுக்குத் தேவன் தம்முடைய அன்பினால் இலவசமாகக் கொடுக்கிற இரக்கமும் தயவும்.","definition_en":"The unmerited favor and divine assistance given by God to man.","examples":[{"sentence_ta":"விசுவாசத்தைக் கொண்டு கிருபையினாலே இரட்சிக்கப்பட்டீர்கள்.","sentence_en":"By grace are ye saved through faith."},{"sentence_ta":"என் கிருபை உனக்குப் போதும்; பலவீனத்திலே என் பலம் பூரணமாய் விளங்கும்.","sentence_en":"My grace is sufficient for thee: for my strength is made perfect in weakness."}],"original":{"lang":"${isOT ? 'he' : 'grc'}","lemma":"${isOT ? 'חֶסֶד' : 'χάρις'}","strongs":"${isOT ? 'H2617' : 'G5485'}"},"modern_equivalents":["இலவச தயவு"],"see_also":[],"notes":"பழைய ஏற்பாட்டில் மாறாத உடன்படிக்கை அன்பையும் (chesed), புதிய ஏற்பாட்டில் இலவச ஈவையும் (charis) குறிக்கிறது."}]}`;
}

// ---------------------------------------------------------------------------
// Chapter Processing with Automatic Chunking
// ---------------------------------------------------------------------------
function cleanAndParseJson(rawContent) {
  let clean = rawContent.trim();
  clean = clean.replace(/^```json\s*/i, '').replace(/^```\s*/, '').replace(/```\s*$/, '').trim();

  try {
    return JSON.parse(clean);
  } catch (err) {
    // Robust brace-depth parser: extracts all complete top-level entry objects
    const entries = [];
    let inString = false;
    let escape = false;
    let braceDepth = 0;
    let startIdx = -1;

    for (let i = 0; i < clean.length; i++) {
      const char = clean[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (char === '\\') {
        escape = true;
        continue;
      }
      if (char === '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char === '{') {
        // If at top level or directly inside entries array
        if (braceDepth === 1 || braceDepth === 0) {
          startIdx = i;
        }
        braceDepth++;
      } else if (char === '}') {
        braceDepth--;
        if ((braceDepth === 1 || braceDepth === 0) && startIdx !== -1) {
          const candidate = clean.slice(startIdx, i + 1);
          try {
            const obj = JSON.parse(candidate);
            if (obj && obj.id && obj.headword) {
              entries.push(obj);
            } else if (obj && Array.isArray(obj.entries)) {
              return obj;
            }
          } catch (e) {}
          startIdx = -1;
        }
      }
    }

    if (entries.length > 0) {
      console.warn(`[cleanAndParseJson: Recovered ${entries.length} complete entries from truncated response]`);
      return { entries };
    }

    console.error('Failed to parse JSON. Raw content ending:');
    console.error(clean.slice(-500));
    throw new Error(`Failed to parse JSON response: ${err.message}`);
  }
}

function getTamilStems(hw) {
  const stems = new Set();

  // Strip noun endings ONLY if resulting stem has >= 2 syllables (UTF-16 length >= 3)
  // Only ம் (which changes to த்த / ம) and ன் (which changes to ன / ர) drop in Tamil declension.
  if (hw.endsWith('ம்')) {
    const base = hw.slice(0, -2);
    if (base.length >= 3) {
      stems.add(base); // e.g. கூடாரம் -> கூடார, தோட்டம் -> தோட்ட
      stems.add(base + 'ம'); // e.g. ஆதாம் -> ஆதாம (for ஆதாமின்)
    }
  } else if (hw.endsWith('ன்')) {
    const base = hw.slice(0, -2);
    if (base.length >= 3) {
      stems.add(base); // e.g. தேவன் -> தேவ, மனுஷன் -> மனுஷ
      stems.add(base + 'ன'); // e.g. தேவனை, தேவனுக்கு
      stems.add(base + 'ர'); // e.g. மனுஷர்
    }
  }

  // Include full headword as stem only if length >= 3 (never allow single-syllable stems like சா, தீ, பூ, வா)
  if (hw.length >= 3) {
    stems.add(hw);
  }

  return Array.from(stems).filter(s => s.length >= 3);
}

export class GlobalLexiconTracker {
  constructor() {
    this.knownHeadwords = new Set();
    this.formToHeadword = new Map();
    this.headwordStemsMap = new Map();
  }

  loadFromCache(cacheDir) {
    if (!fs.existsSync(cacheDir)) return;
    const files = fs.readdirSync(cacheDir).filter(f => f.endsWith('.json'));
    for (const f of files) {
      try {
        const entries = JSON.parse(fs.readFileSync(path.join(cacheDir, f), 'utf8'));
        this.registerEntries(entries);
      } catch {}
    }
  }

  registerEntries(entries) {
    for (const e of entries) {
      if (!e.headword) continue;
      const hw = e.headword.trim();
      this.knownHeadwords.add(hw);
      this.formToHeadword.set(hw, hw);
      (e.forms || []).forEach(f => this.formToHeadword.set(f.trim(), hw));
      const stems = getTamilStems(hw);
      for (const s of stems) {
        this.headwordStemsMap.set(s, hw);
      }
    }
  }

  getOverlappingHeadwords(verses) {
    const text = verses.map(v => v.text).join(' ');
    const tokens = new Set(
      text.replace(/[^\u0B80-\u0BFF\s]/g, ' ')
        .split(/\s+/)
        .map(t => t.trim())
        .filter(t => t.length > 0)
    );

    const matched = new Set();
    for (const token of tokens) {
      if (this.formToHeadword.has(token)) {
        matched.add(this.formToHeadword.get(token));
        continue;
      }
      if (this.knownHeadwords.has(token)) {
        matched.add(token);
        continue;
      }
      for (const [stem, hw] of this.headwordStemsMap.entries()) {
        if (token.startsWith(stem) && token.length <= stem.length + 15) {
          matched.add(hw);
        }
      }
    }
    return Array.from(matched).sort();
  }
}

async function processChapterChunk(bookNum, chapterNum, verses, chunkLabel = '', alreadyExtracted = []) {
  const isOT = bookNum <= 39;
  const osis = OSIS_BOOK_CODES[bookNum] || `B${bookNum}`;
  const systemPrompt = buildSystemPrompt(isOT);

  // Format verses as clean numbered lines for optimal token efficiency
  const verseLines = verses.map(v => `${v.verse}. ${v.text}`).join('\n');
  let userPrompt = `Analyze the passage: ${osis} Chapter ${chapterNum} ${chunkLabel}\n\n`;

  if (alreadyExtracted.length > 0) {
    userPrompt += `CRITICAL EXCLUSION LIST (ALREADY EXTRACTED WORDS - DO NOT RE-EXTRACT):\n`;
    userPrompt += `The following ${alreadyExtracted.length} words have ALREADY been extracted and indexed from previous passages. Under NO circumstances should any of them (or their inflected forms) be included in your output:\n`;
    userPrompt += `[ ${alreadyExtracted.join(', ')} ]\n\n`;
  }

  userPrompt += `Tamil Bible Text (TAOVBSI):\n${verseLines}\n\n`;

  if (alreadyExtracted.length > 0) {
    userPrompt += `STRICT INSTRUCTION:\n`;
    userPrompt += `Extract 12 to 15 rich, distinct content words (nouns, verbs, adjectives, proper names) from the verses above that are NOT in the exclusion list.\n`;
    userPrompt += `Words such as "${alreadyExtracted.slice(0, 5).join('", "')}" must be skipped entirely.\n`;
  } else {
    userPrompt += `Extract 12 to 15 rich, distinct content words from this passage according to the required schema.\n`;
  }

  const response = await callDeepSeek([
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userPrompt }
  ]);

  const rawContent = response.choices[0].message.content.trim();
  const parsed = cleanAndParseJson(rawContent);

  const rawEntries = parsed.entries || (Array.isArray(parsed) ? parsed : []);
  const excludedSet = new Set(alreadyExtracted.map(w => w.trim()));
  const filteredEntries = rawEntries.filter(e => {
    if (!e.headword) return false;
    const hw = e.headword.trim();
    if (excludedSet.has(hw)) {
      return false;
    }
    return true;
  });

  return {
    entries: filteredEntries,
    usage: response.usage || {}
  };
}

export async function processChapter(bookNum, chapterNum, globalTracker = null) {
  const chapterFilePath = path.join(BIBLE_DIR, String(bookNum), `${chapterNum}.json`);
  if (!fs.existsSync(chapterFilePath)) {
    throw new Error(`File not found: ${chapterFilePath}`);
  }

  const verses = JSON.parse(fs.readFileSync(chapterFilePath, 'utf8'));
  const MAX_WHOLE_CHAPTER_VERSES = 75; // 99% of chapters have <= 70 verses
  const currentChapterHeadwords = new Set();

  // If chapter has more than MAX_WHOLE_CHAPTER_VERSES (only Psalm 119, Numbers 7, 1 Chron 6), split into 2 halves
  if (verses.length > MAX_WHOLE_CHAPTER_VERSES) {
    const half = Math.ceil(verses.length / 2);
    const chunkPromises = [
      { verses: verses.slice(0, half), label: `(Part 1/2, Verses 1–${half})` },
      { verses: verses.slice(half), label: `(Part 2/2, Verses ${half + 1}–${verses.length})` }
    ];

    const allEntries = [];
    let totalPromptTokens = 0;
    let totalCompletionTokens = 0;

    for (const chunk of chunkPromises) {
      // Cross-chapter + intra-chapter overlapping headwords
      const globalOverlaps = globalTracker ? globalTracker.getOverlappingHeadwords(chunk.verses) : [];
      const combinedExclusions = Array.from(new Set([...globalOverlaps, ...currentChapterHeadwords]));

      const res = await processChapterChunk(bookNum, chapterNum, chunk.verses, chunk.label, combinedExclusions);
      
      for (const e of res.entries) {
        if (e.headword) currentChapterHeadwords.add(e.headword.trim());
      }
      if (globalTracker && res.entries.length > 0) {
        globalTracker.registerEntries(res.entries);
      }

      allEntries.push(...res.entries);
      totalPromptTokens += res.usage.prompt_tokens || 0;
      totalCompletionTokens += res.usage.completion_tokens || 0;
    }

    // Merge entries by canonical Tamil headword
    const entryMap = new Map();
    for (const e of allEntries) {
      if (!e.headword) continue;
      const key = e.headword.trim();
      if (!entryMap.has(key)) {
        entryMap.set(key, e);
      } else {
        const existing = entryMap.get(key);
        // Union forms
        const existingForms = new Set(existing.forms || []);
        (e.forms || []).forEach(f => existingForms.add(f));
        existing.forms = Array.from(existingForms);
        // Union see_also
        const existingSeeAlso = new Set(existing.see_also || []);
        (e.see_also || []).forEach(s => existingSeeAlso.add(s));
        existing.see_also = Array.from(existingSeeAlso);
        // Union modern_equivalents
        const existingMod = new Set(existing.modern_equivalents || []);
        (e.modern_equivalents || []).forEach(m => existingMod.add(m));
        existing.modern_equivalents = Array.from(existingMod);
        // Keep richest definition
        if ((e.definition_ta || '').length > (existing.definition_ta || '').length) {
          existing.definition_ta = e.definition_ta;
        }
        if ((e.definition_en || '').length > (existing.definition_en || '').length) {
          existing.definition_en = e.definition_en;
        }
      }
    }

    return {
      entries: Array.from(entryMap.values()),
      usage: {
        prompt_tokens: totalPromptTokens,
        completion_tokens: totalCompletionTokens,
        total_tokens: totalPromptTokens + totalCompletionTokens
      }
    };
  } else {
    // Standard chapters (<= 75 verses): Process as a single whole chapter
    const globalOverlaps = globalTracker ? globalTracker.getOverlappingHeadwords(verses) : [];
    const res = await processChapterChunk(bookNum, chapterNum, verses, `(Verses 1–${verses.length})`, globalOverlaps);
    if (globalTracker && res.entries.length > 0) {
      globalTracker.registerEntries(res.entries);
    }
    return res;
  }
}

// ---------------------------------------------------------------------------
// Status Manager
// ---------------------------------------------------------------------------
function loadStatus() {
  if (fs.existsSync(STATUS_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(STATUS_FILE, 'utf8'));
    } catch {}
  }
  return {
    last_updated: new Date().toISOString(),
    total_chapters: 1189,
    completed: 0,
    failed: 0,
    total_prompt_tokens: 0,
    total_completion_tokens: 0,
    chapters: {}
  };
}

function saveStatus(status) {
  status.last_updated = new Date().toISOString();
  fs.writeFileSync(STATUS_FILE, JSON.stringify(status, null, 2), 'utf8');
}

// ---------------------------------------------------------------------------
// Compiler: Local Deduplication & Mathematical Verse Indexer
// ---------------------------------------------------------------------------
export function compileGlossaryDatabase() {
  console.log('\n=== COMPILING TAOVBSI GLOSSARY DATABASE (POST-PROCESSING) ===');
  const chapterFiles = fs.readdirSync(CHAPTERS_CACHE_DIR)
    .filter(f => f.startsWith('b') && f.endsWith('.json'))
    .sort();

  if (chapterFiles.length === 0) {
    console.log('No chapter JSON files found to compile in:', CHAPTERS_CACHE_DIR);
    return;
  }

  console.log(`Loading and merging ${chapterFiles.length} chapter files...`);

  // 1. Group & Merge by Lemma ID
  const masterLexicon = new Map(); // id -> entry

  for (const file of chapterFiles) {
    const raw = fs.readFileSync(path.join(CHAPTERS_CACHE_DIR, file), 'utf8');
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      continue;
    }

    const entries = Array.isArray(data) ? data : (data.entries || []);
    for (const e of entries) {
      if (!e.id || !e.headword) continue;
      const key = e.id.toLowerCase().trim();

      if (!masterLexicon.has(key)) {
        masterLexicon.set(key, {
          id: key,
          headword: e.headword.trim(),
          transliteration: e.transliteration || '',
          pos: (e.pos || 'noun').toLowerCase(),
          pos_ta: e.pos_ta || 'பெயர்ச்சொல்',
          category: e.category || 'other',
          gloss_en: e.gloss_en || '',
          definition_ta: e.definition_ta || '',
          definition_en: e.definition_en || '',
          original: e.original || null,
          modern_equivalents: new Set(e.modern_equivalents || []),
          see_also: new Set(e.see_also || []),
          notes: e.notes || '',
          examples: Array.isArray(e.examples) ? e.examples : [],
          forms: new Set(e.forms || [e.headword])
        });
      } else {
        const item = masterLexicon.get(key);
        // Union forms
        (e.forms || []).forEach(f => item.forms.add(f.trim()));
        // Union see_also
        (e.see_also || []).forEach(s => item.see_also.add(s.trim()));
        // Union modern_equivalents
        (e.modern_equivalents || []).forEach(m => item.modern_equivalents.add(m.trim()));
        if (!item.transliteration && e.transliteration) item.transliteration = e.transliteration;
        if (!item.category && e.category) item.category = e.category;
        if (!item.notes && e.notes) item.notes = e.notes;
        if ((!item.examples || item.examples.length === 0) && Array.isArray(e.examples) && e.examples.length > 0) {
          item.examples = e.examples;
        }
        // Keep longest definition
        if ((e.definition_ta || '').length > item.definition_ta.length) {
          item.definition_ta = e.definition_ta;
        }
        if ((e.definition_en || '').length > item.definition_en.length) {
          item.definition_en = e.definition_en;
        }
      }
    }
  }

  console.log(`Deduplication complete: ${masterLexicon.size} unique lexical headwords.`);

  // 2. Build Inverted Surface Form Index
  const formToLemma = new Map(); // surface_form -> lemma_id
  for (const [id, entry] of masterLexicon.entries()) {
    formToLemma.set(entry.headword, id);
    for (const f of entry.forms) {
      formToLemma.set(f, id);
    }
  }
  console.log(`Indexed ${formToLemma.size} unique surface forms across all lemmas.`);

  // 3. Mathematical Verse Reference Indexing from Bible text
  console.log('Mapping exact verse occurrences from TAOVBSI Bible text...');
  const lemmaRefs = new Map(); // lemma_id -> Set of 'OSIS.ch.v'
  const verseOccurrences = []; // { book, chapter, verse, entry_id, surface_form }

  for (let b = 1; b <= 66; b++) {
    const bDir = path.join(BIBLE_DIR, String(b));
    if (!fs.existsSync(bDir)) continue;
    const osis = OSIS_BOOK_CODES[b] || `B${b}`;

    for (const f of fs.readdirSync(bDir)) {
      if (!f.endsWith('.json')) continue;
      const chNum = parseInt(f.replace('.json', ''));
      const verses = JSON.parse(fs.readFileSync(path.join(bDir, f), 'utf8'));

      for (const v of verses) {
        const tokens = v.text
          .replace(/[\.,;:!\?\"\'\(\)\—\–\[\]0-9]/g, ' ')
          .split(/\s+/)
          .map(t => t.trim())
          .filter(t => t.length > 0);

        for (const token of tokens) {
          if (formToLemma.has(token)) {
            const lemmaId = formToLemma.get(token);
            const refStr = `${osis}.${chNum}.${v.verse}`;

            if (!lemmaRefs.has(lemmaId)) lemmaRefs.set(lemmaId, new Set());
            lemmaRefs.get(lemmaId).add(refStr);

            verseOccurrences.push({
              book: b,
              chapter: chNum,
              verse: v.verse,
              entry_id: lemmaId,
              surface_form: token
            });
          }
        }
      }
    }
  }

  // 4. Create SQLite Database
  if (fs.existsSync(SQLITE_OUT)) fs.unlinkSync(SQLITE_OUT);
  const db = new DatabaseSync(SQLITE_OUT);

  db.exec('PRAGMA journal_mode = WAL;');
  db.exec('PRAGMA synchronous = NORMAL;');

  db.exec(`
    CREATE TABLE IF NOT EXISTS glossary_entries (
      id TEXT PRIMARY KEY,
      headword TEXT NOT NULL,
      transliteration TEXT,
      pos TEXT NOT NULL,
      pos_ta TEXT NOT NULL,
      category TEXT,
      gloss_en TEXT NOT NULL,
      definition_ta TEXT NOT NULL,
      definition_en TEXT NOT NULL,
      examples TEXT,
      original_lang TEXT,
      original_lemma TEXT,
      strongs TEXT,
      modern_equivalents TEXT,
      see_also TEXT,
      notes TEXT,
      forms TEXT,
      refs TEXT,
      occurrence_count INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS surface_forms (
      surface_form TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES glossary_entries(id)
    );

    CREATE TABLE IF NOT EXISTS verse_glossary (
      book INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      entry_id TEXT NOT NULL REFERENCES glossary_entries(id),
      surface_form TEXT NOT NULL,
      PRIMARY KEY (book, chapter, verse, entry_id, surface_form)
    );

    CREATE INDEX IF NOT EXISTS idx_verse_glossary_bcv ON verse_glossary(book, chapter, verse);
    CREATE INDEX IF NOT EXISTS idx_surface_forms_entry ON surface_forms(entry_id);

    CREATE VIRTUAL TABLE IF NOT EXISTS glossary_fts USING fts5(
      id,
      headword,
      transliteration,
      gloss_en,
      definition_ta,
      definition_en,
      content='glossary_entries',
      content_rowid='rowid'
    );
  `);

  const insertEntry = db.prepare(`
    INSERT INTO glossary_entries (
      id, headword, transliteration, pos, pos_ta, category, gloss_en, definition_ta, definition_en,
      examples, original_lang, original_lemma, strongs, modern_equivalents, see_also, notes, forms, refs, occurrence_count
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertSurfaceForm = db.prepare(`
    INSERT OR IGNORE INTO surface_forms (surface_form, entry_id) VALUES (?, ?)
  `);

  const insertVerseGlossary = db.prepare(`
    INSERT OR IGNORE INTO verse_glossary (book, chapter, verse, entry_id, surface_form)
    VALUES (?, ?, ?, ?, ?)
  `);

  const insertFts = db.prepare(`
    INSERT INTO glossary_fts (rowid, id, headword, transliteration, gloss_en, definition_ta, definition_en)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  console.log('Writing into SQLite database...');
  db.exec('BEGIN TRANSACTION;');

  let rowid = 1;
  for (const [id, item] of masterLexicon.entries()) {
    const refsArr = Array.from(lemmaRefs.get(id) || []);
    const formsArr = Array.from(item.forms);
    const modernArr = Array.from(item.modern_equivalents);
    const seeAlsoArr = Array.from(item.see_also);

    insertEntry.run(
      item.id,
      item.headword,
      item.transliteration || '',
      item.pos,
      item.pos_ta,
      item.category || 'other',
      item.gloss_en,
      item.definition_ta,
      item.definition_en,
      JSON.stringify(item.examples || []),
      item.original?.lang || null,
      item.original?.lemma || null,
      item.original?.strongs || null,
      JSON.stringify(modernArr),
      JSON.stringify(seeAlsoArr),
      item.notes || '',
      JSON.stringify(formsArr),
      JSON.stringify(refsArr),
      refsArr.length
    );

    insertFts.run(
      rowid,
      item.id,
      item.headword,
      item.transliteration || '',
      item.gloss_en,
      item.definition_ta,
      item.definition_en
    );

    // Insert surface forms
    for (const form of formsArr) {
      insertSurfaceForm.run(form, item.id);
    }

    rowid++;
  }

  // Insert verse occurrences
  for (const occ of verseOccurrences) {
    insertVerseGlossary.run(occ.book, occ.chapter, occ.verse, occ.entry_id, occ.surface_form);
  }

  db.exec('COMMIT;');
  db.close();

  // Compress to .gz
  console.log('Compressing SQLite to gzip...');
  const dbBytes = fs.readFileSync(SQLITE_OUT);
  fs.writeFileSync(SQLITE_GZ_OUT, zlib.gzipSync(dbBytes, { level: 9 }));

  const rawMb = (dbBytes.length / (1024 * 1024)).toFixed(2);
  const gzMb = (fs.statSync(SQLITE_GZ_OUT).size / (1024 * 1024)).toFixed(2);

  console.log(`Compilation Complete!`);
  console.log(`  Output SQLite: ${SQLITE_OUT} (${rawMb} MB)`);
  console.log(`  Compressed GZ: ${SQLITE_GZ_OUT} (${gzMb} MB)`);
  console.log(`  Master Lexicon Entries: ${masterLexicon.size}`);
  console.log(`  Total Surface Forms Mapped: ${formToLemma.size}`);
  console.log(`  Total Verse Cross-references: ${verseOccurrences.length}`);
}

// ---------------------------------------------------------------------------
// Test Mode: Genesis 1–3
// ---------------------------------------------------------------------------
async function runTestMode() {
  console.log('=== RUNNING TAOVBSI GLOSSARY TEST MODE (Genesis 1–3) ===\n');

  const testChapters = [
    { b: 1, c: 1, name: 'Genesis 1' },
    { b: 1, c: 2, name: 'Genesis 2' },
    { b: 1, c: 3, name: 'Genesis 3' }
  ];

  const testTracker = new GlobalLexiconTracker();

  for (const item of testChapters) {
    console.log(`\nProcessing ${item.name}...`);
    const startTime = Date.now();
    const result = await processChapter(item.b, item.c, testTracker);
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    console.log(`Completed in ${elapsed}s! Extracted ${result.entries.length} terms.`);
    console.log(`Tokens - Prompt: ${result.usage.prompt_tokens}, Completion: ${result.usage.completion_tokens}`);

    // Save to cache
    const cacheFile = path.join(CHAPTERS_CACHE_DIR, `b${String(item.b).padStart(2, '0')}_c${String(item.c).padStart(3, '0')}.json`);
    fs.writeFileSync(cacheFile, JSON.stringify(result.entries, null, 2), 'utf8');
    console.log(`Saved to cache: ${cacheFile}`);

    // Display sample entries
    console.log(`Sample Extractions from ${item.name}:`);
    result.entries.slice(0, 3).forEach(e => {
      console.log(`  • [${e.pos}] ${e.headword} (${e.id}) -> "${e.gloss_en}"`);
      console.log(`    Forms: ${JSON.stringify(e.forms)}`);
      console.log(`    Original: ${e.original?.lang} ${e.original?.lemma} [${e.original?.strongs}]`);
      console.log(`    Modern: ${JSON.stringify(e.modern_equivalents)}`);
      console.log(`    Def TA: ${e.definition_ta.slice(0, 80)}...`);
      console.log(`    Notes: ${e.notes || '(none)'}`);
      if (e.examples && e.examples.length > 0) {
        console.log(`    Examples (${e.examples.length}):`);
        e.examples.forEach((ex, idx) => {
          console.log(`      [${idx + 1}] TA: ${ex.sentence_ta}`);
          console.log(`          EN: ${ex.sentence_en}`);
        });
      }
    });
  }

  // Compile test database
  console.log('\nRunning test compile pass...');
  compileGlossaryDatabase();
}

// ---------------------------------------------------------------------------
// Batch Runner for Whole Bible
// ---------------------------------------------------------------------------
async function runBatch(options = {}) {
  const books = JSON.parse(fs.readFileSync(BOOKS_FILE, 'utf8'));
  const status = loadStatus();

  // Build chapter queue
  const queue = [];
  for (const book of books) {
    if (options.book && book.bookNumber !== options.book) continue;
    for (let c = 1; c <= book.chapters; c++) {
      const key = `b${String(book.bookNumber).padStart(2, '0')}_c${String(c).padStart(3, '0')}`;
      const cacheFile = path.join(CHAPTERS_CACHE_DIR, `${key}.json`);

      // Skip already completed unless force
      if (!options.force && fs.existsSync(cacheFile) && status.chapters[key]?.status === 'completed') {
        continue;
      }
      queue.push({ b: book.bookNumber, c, key });
    }
  }

  if (options.limit && queue.length > options.limit) {
    queue.splice(options.limit);
  }

  console.log(`Queue size: ${queue.length} chapters to process.`);
  if (queue.length === 0) {
    console.log('All targeted chapters already completed!');
    return;
  }

  const concurrency = options.concurrency || 1; // Strictly sequential by default to prevent cross-chapter race conditions
  console.log(`Starting execution with concurrency: ${concurrency} (sequential: ${concurrency === 1})...`);

  const tracker = new GlobalLexiconTracker();
  tracker.loadFromCache(CHAPTERS_CACHE_DIR);
  console.log(`Global Lexicon Tracker initialized with ${tracker.knownHeadwords.size} unique headwords.`);

  let active = 0;
  let index = 0;

  return new Promise((resolve) => {
    function next() {
      if (index >= queue.length && active === 0) {
        console.log('\nAll queued chapters completed!');
        return resolve();
      }

      while (active < concurrency && index < queue.length) {
        const item = queue[index++];
        active++;

        (async () => {
          console.log(`[Start] Book ${item.b} Chapter ${item.c}... (${index}/${queue.length})`);
          try {
            const res = await processChapter(item.b, item.c, tracker);
            const cacheFile = path.join(CHAPTERS_CACHE_DIR, `${item.key}.json`);
            fs.writeFileSync(cacheFile, JSON.stringify(res.entries, null, 2), 'utf8');

            status.completed++;
            status.total_prompt_tokens += res.usage.prompt_tokens || 0;
            status.total_completion_tokens += res.usage.completion_tokens || 0;
            status.chapters[item.key] = {
              status: 'completed',
              terms_count: res.entries.length,
              completed_at: new Date().toISOString()
            };
            saveStatus(status);
            console.log(`[Done] Book ${item.b} Chapter ${item.c} - Extracted ${res.entries.length} terms.`);
          } catch (err) {
            console.error(`[Error] Book ${item.b} Chapter ${item.c}:`, err.message);
            status.failed++;
            status.chapters[item.key] = {
              status: 'failed',
              error: err.message,
              failed_at: new Date().toISOString()
            };
            saveStatus(status);
          } finally {
            active--;
            next();
          }
        })();
      }
    }

    next();
  });
}

// ---------------------------------------------------------------------------
// CLI Dispatcher
// ---------------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--test')) {
    await runTestMode();
    return;
  }

  if (args.includes('--compile')) {
    compileGlossaryDatabase();
    return;
  }

  if (args.includes('--status')) {
    const s = loadStatus();
    const USD_TO_INR = 86.5;
    const inputCostUsd = (s.total_prompt_tokens / 1000000) * 0.14;
    const outputCostUsd = (s.total_completion_tokens / 1000000) * 0.28;
    const totalCostUsd = inputCostUsd + outputCostUsd;
    const totalCostInr = totalCostUsd * USD_TO_INR;

    const pct = ((s.completed / s.total_chapters) * 100).toFixed(1);
    const avgCostPerChInr = s.completed > 0 ? (totalCostInr / s.completed).toFixed(2) : '0.00';
    const projectedTotalInr = s.completed > 0 ? ((totalCostInr / s.completed) * s.total_chapters).toFixed(0) : '200';

    console.log('\n=== TAOVBSI GLOSSARY EXTRACTION LIVE STATUS ===');
    console.log(`Progress: ${s.completed} / ${s.total_chapters} chapters (${pct}%)`);
    console.log(`Failed: ${s.failed}`);
    console.log(`Tokens - Prompt: ${s.total_prompt_tokens.toLocaleString()}, Completion: ${s.total_completion_tokens.toLocaleString()}`);
    console.log(`-----------------------------------------------`);
    console.log(`Cost Spent So Far: ₹${totalCostInr.toFixed(2)} INR ($${totalCostUsd.toFixed(4)} USD)`);
    console.log(`Average Cost per Chapter: ₹${avgCostPerChInr} INR (~${(avgCostPerChInr * 100).toFixed(0)} paise)`);
    console.log(`Estimated Total Bible Cost: ₹${projectedTotalInr} INR`);
    console.log(`===============================================\n`);
    return;
  }

  const bookArgIdx = args.indexOf('--book');
  const book = bookArgIdx !== -1 ? parseInt(args[bookArgIdx + 1]) : null;

  const limitArgIdx = args.indexOf('--limit');
  const limit = limitArgIdx !== -1 ? parseInt(args[limitArgIdx + 1]) : null;

  const concArgIdx = args.indexOf('--concurrency');
  const concurrency = concArgIdx !== -1 ? parseInt(args[concArgIdx + 1]) : 1;

  if (args.includes('--all') || book !== null) {
    await runBatch({ book, limit, concurrency });
    console.log('\nProcessing done. Running compilation...');
    compileGlossaryDatabase();
  } else {
    console.log(`
Usage:
  node tool/build_taobvsi_glossary_deepseek.mjs --test
  node tool/build_taobvsi_glossary_deepseek.mjs --status
  node tool/build_taobvsi_glossary_deepseek.mjs --book <number>
  node tool/build_taobvsi_glossary_deepseek.mjs --all [--concurrency 5]
  node tool/build_taobvsi_glossary_deepseek.mjs --compile
`);
  }
}

main().catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
