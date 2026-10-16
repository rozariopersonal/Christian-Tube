#!/usr/bin/env node
/**
 * tool/build_scriptures_deepseek.mjs
 * 
 * Production scripture feed builder using DeepSeek-V3 (deepseek-chat)
 * reading from the World English Bible (releases/bibles/web/).
 * 
 * Features:
 * - 4 LLM output fields + Top-5 ranked master tags (from 60-tag taxonomy).
 * - Fault-tolerant: per-chapter caching, automatic retries with exponential backoff.
 * - Auto-recovery: automatically sweeps and heals any transiently failed chapters.
 * - Automatic pipeline execution upon completion of all 1,189 chapters:
 *     1. releases/scriptures.json (and apps/backend/data/scriptures.json mirror)
 *     2. releases/scriptures.sqlite + releases/scriptures.sqlite.gz (with FTS5 search)
 *     3. releases/words_feed/ (daily.json, topic files, letter shards, manifest.json)
 *     4. releases/manifest.json revision bump (per AGENTS.md rule)
 * - Comprehensive `--test` mode to verify end-to-end functionality before triggering.
 * 
 * Usage:
 *   node tool/build_scriptures_deepseek.mjs --test
 *   node tool/build_scriptures_deepseek.mjs --status
 *   node tool/build_scriptures_deepseek.mjs --all
 *   node tool/build_scriptures_deepseek.mjs --limit 10
 *   node tool/build_scriptures_deepseek.mjs --compile
 */

import fs from 'fs';
import path from 'path';
import zlib from 'zlib';
import { fileURLToPath } from 'url';
import { DatabaseSync } from 'node:sqlite';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const API_KEY = process.env.DEEPSEEK_API_KEY || 'sk-f514d1a1c6e14901a79ed5d290af9e51';
const API_URL = 'https://api.deepseek.com/chat/completions';
const MODEL_ID = 'deepseek-chat';

const CACHE_DIR = path.join(ROOT, '.cache', 'scriptures_deepseek');
const CHAPTERS_CACHE_DIR = path.join(CACHE_DIR, 'chapters');
const STATUS_FILE = path.join(CACHE_DIR, 'status.json');
const COMPILED_FILE = path.join(CACHE_DIR, 'scriptures_compiled.json');

const RELEASES_DIR = path.join(ROOT, 'releases');
const CANONICAL_SCRIPTURES = path.join(RELEASES_DIR, 'scriptures.json');
const BACKEND_SCRIPTURES = path.join(ROOT, 'apps', 'backend', 'data', 'scriptures.json');
const SQLITE_OUT = path.join(RELEASES_DIR, 'scriptures.sqlite');
const SQLITE_GZ_OUT = path.join(RELEASES_DIR, 'scriptures.sqlite.gz');
const WORDS_FEED_DIR = path.join(RELEASES_DIR, 'words_feed');
const MANIFEST_FILE = path.join(RELEASES_DIR, 'manifest.json');
const BOOKS_FILE = path.join(RELEASES_DIR, 'bibles', 'web', 'books.json');

const CATEGORIES = [
  'words_of_god',
  'jesus_words',
  'prophecy',
  'promise',
  'commandment',
  'wisdom',
  'doctrine',
  'comfort',
  'warning',
  'prayer',
  'praise',
  'salvation',
  'faith',
  'repentance',
  'miracle',
  'parable',
  'divine_action',
  'consecration',
];

const MASTER_TAGS = [
  // God & Trinity
  'god_character', 'sovereignty', 'holiness', 'mercy_grace', 'christ_messiah', 'holy_spirit', 'trinity',
  // Gospel & Salvation
  'salvation', 'the_cross', 'resurrection', 'faith', 'forgiveness', 'repentance', 'eternal_life', 'justification',
  // Inner Devotion
  'prayer', 'worship_praise', 'thanksgiving', 'obedience', 'consecration', 'humility', 'word_of_god', 'fear_of_god', 'seeking_god', 'discipleship',
  // Trials & Emotional Peace
  'peace', 'comfort', 'hope', 'anxiety_fear', 'suffering_trials', 'joy', 'healing', 'perseverance', 'deliverance',
  // Character & Conduct
  'love', 'purity', 'wisdom', 'integrity', 'patience', 'courage', 'self_control', 'generosity', 'truth', 'righteousness',
  // Relationships & Community
  'marriage', 'family', 'fellowship_unity', 'service', 'forgiving_others', 'edification',
  // Warnings & Warfare
  'spiritual_warfare', 'temptation', 'pride', 'sin_warning', 'deceit', 'worldliness', 'idolatry',
  // Covenant & Future Hope
  'covenant', 'prophecy', 'second_coming', 'kingdom_of_god', 'heaven', 'judgment', 'eternal_reward'
];

const BG_PRESETS = ['mountain_dawn', 'ocean_calm', 'desert_dusk', 'forest_sun', 'starry_night'];

// ---------------------------------------------------------------------------
// Helpers & State Persistence
// ---------------------------------------------------------------------------
function ensureDirs() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
  if (!fs.existsSync(CHAPTERS_CACHE_DIR)) fs.mkdirSync(CHAPTERS_CACHE_DIR, { recursive: true });
}

function loadStatus() {
  if (fs.existsSync(STATUS_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(STATUS_FILE, 'utf8'));
    } catch {
      // fallback
    }
  }
  return {
    totalChapters: 1189,
    completed: {}, // key: "b{book}_c{chapter}" -> { count, timestamp }
    failed: {},    // key: "b{book}_c{chapter}" -> { error, timestamp }
    totalPassagesExtracted: 0,
    totalTokens: 0,
    totalCostUSD: 0,
    lastRunAt: null,
  };
}

function saveStatus(status) {
  status.lastRunAt = new Date().toISOString();
  fs.writeFileSync(STATUS_FILE, JSON.stringify(status, null, 2), 'utf8');
}

function loadBooks() {
  if (!fs.existsSync(BOOKS_FILE)) {
    const kjvBooks = path.join(RELEASES_DIR, 'bibles', 'kjv', 'books.json');
    return JSON.parse(fs.readFileSync(kjvBooks, 'utf8'));
  }
  return JSON.parse(fs.readFileSync(BOOKS_FILE, 'utf8'));
}

function loadChapterVerses(bookNum, chapter) {
  const localWeb = path.join(RELEASES_DIR, 'bibles', 'web', String(bookNum), `${chapter}.json`);
  if (fs.existsSync(localWeb)) {
    return JSON.parse(fs.readFileSync(localWeb, 'utf8'));
  }
  const localKjv = path.join(RELEASES_DIR, 'bibles', 'kjv', String(bookNum), `${chapter}.json`);
  if (fs.existsSync(localKjv)) {
    return JSON.parse(fs.readFileSync(localKjv, 'utf8'));
  }
  throw new Error(`Chapter not found locally: ${bookNum}:${chapter}`);
}

// ---------------------------------------------------------------------------
// Context Loader & Prompt Builder
// ---------------------------------------------------------------------------
function getNeighborContext(books, bookIndex, chapter) {
  const currentBook = books[bookIndex];
  if (!currentBook) return { prev: null, next: null };

  let prev = null;
  let next = null;

  if (chapter > 1) {
    try {
      prev = {
        book: currentBook.name,
        chapter: chapter - 1,
        verses: loadChapterVerses(currentBook.bookNumber, chapter - 1),
      };
    } catch (_) {}
  }

  if (chapter < currentBook.chapters) {
    try {
      next = {
        book: currentBook.name,
        chapter: chapter + 1,
        verses: loadChapterVerses(currentBook.bookNumber, chapter + 1),
      };
    } catch (_) {}
  }

  return { prev, next };
}

function buildPrompt(bookName, chapter, verses, prev = null, next = null) {
  return `ROLE AND MISSION

You are an expert biblical scholar and devotional editor curating a daily Scripture feed for Christian disciples seeking genuine spiritual growth. From one chapter of the World English Bible (WEB), you select passages that are genuinely valuable for New Covenant devotional formation, classify them, and return JSON.

Editorial focus: Christlike character; faith, love, humility, holiness, obedience; prayer, repentance, worship, gratitude; God's character and redemptive purposes; the gospel and what God has done in Christ; faithful examples and restoration; Jesus' teaching, cross, resurrection, and example.

This is selective curation, NOT commentary. A chapter may yield many passages, a few, or none. Never invent devotional relevance to fill a quota. Rough calibration only: most chapters yield 0-4 passages; rich chapters (e.g. Matthew 5, Romans 8, major Psalms) may yield more; genealogies, ceremonial codes, and boundary or census lists often yield none.

SOURCE FIDELITY

1. Verse numbers and text in the user message are authoritative. Never invent, alter, or infer verse numbers.
2. Select ONLY from the TARGET CHAPTER verses. Any neighboring context is read-only and must never be selected.
3. Do not add quotations, events, or theological claims the text does not support.
4. Interpret within immediate literary and narrative context. Distinguish what the narrator affirms from what a character says or does. Description is not prescription.
5. If a passage cannot be interpreted responsibly from the supplied text and established biblical context, omit it.

HERMENEUTICAL LENS

Use a New Covenant perspective informed by Hebrews 8-10, Romans 6-8, and Matthew 5-7. This is an editorial lens, not permission to force every passage into a predetermined reading.

PRIORITIES (what to look for)

1. INNER LIFE AND CHRISTLIKE CHARACTER: love of God and neighbor (including enemies); humility, mercy, forgiveness; purity of heart, integrity, truthfulness; self-control, perseverance, obedience; repentance, confession, restoration; prayer, worship, thanksgiving; trust in suffering and temptation; wisdom for speech, relationships, work, stewardship; God's steadfast love, holiness, faithfulness, justice, mercy. Select because the theme is genuinely present, not merely associable.

2. JESUS CHRIST: His words, commands, promises; humility, compassion, obedience; prayer and dependence on the Father; treatment of sinners and the suffering; cross, resurrection, redemptive work; kingdom teaching and transformation of the heart. Do not detach a saying from qualifications or surrounding events that affect its meaning.

3. THE GOSPEL AND APOSTOLIC DOCTRINE (first-class targets): grace through faith, justification, forgiveness, reconciliation, redemption, adoption; the meaning of Christ's death, resurrection, ascension, return; the Holy Spirit (indwelling, fruit, gifts, assurance); new identity in Christ and freedom from sin and condemnation; the believer's hope and perseverance; the church (unity, love, service, gifts); spiritual warfare as truth, righteousness, faith, prayer, endurance (never physical violence). Keep an argument's premise and conclusion together; do not isolate a fragment that reads as a different claim; distinguish an author's own teaching from a view quoted to be refuted.

4. FAITHFUL EXAMPLES AND TRANSFORMATION: faith, courage, obedience, self-denial, sacrificial service, dependence on God in weakness, sincere repentance and restoration. Safeguards: (a) never present sinful actions as examples to imitate; (b) one commended action does not make a person's whole character exemplary; (c) you MAY select passages exposing sin when the central contribution is repentance, accountability, restoration, consequences of sin, or God's mercy; (d) do not exclude a passage merely because the person previously failed; (e) do not select a passage just because it mentions someone praised elsewhere; (f) evaluate each passage on its own merits. Hebrews 11 principle: look for demonstrated faith, not blanket moral approval.

FIRM EXCLUSIONS

A. OLD COVENANT CEREMONIAL (Hebrews 9-10; Colossians 2:16-17): EXCLUDE passages whose sole function is to prescribe or describe animal sacrifices and ritual offerings, Levitical priestly procedures and garments, ceremonial impurity and food regulations, Nazirite external requirements, physical circumcision as covenant marker, ritual feast observance, or detailed tabernacle/temple specifications. Do NOT exclude merely because such practices are mentioned. RETAIN passages that explain a practice's theological significance, point to Christ or the New Covenant, reveal God's character, contain enduring moral teaching (e.g. love of neighbor), or give a substantial prophetic promise. Do not present a covenant-specific historical command as a direct New Covenant obligation.

B. VIOLENCE AND IMPRECATION: EXCLUDE passages whose central function is to prescribe physical warfare, celebrate slaughter of enemies as a model for conduct, call for personal vengeance, or wish death, orphanhood, or disaster on human enemies. However: divine judgment is not the same as personal vengeance; laments about injustice, warnings about sin, historical judgment, and statements of God's justice may be eligible if their devotional meaning is substantial. Do not turn a description of violence into a command. Do not exclude a whole chapter just because it contains war or judgment.

GENRE GUIDANCE

PSALMS: Identify the type (praise, thanksgiving, lament, trust, wisdom, royal/messianic, repentance, imprecatory) and select by its central movement. Prefer praise, trust, confession, longing for God, restoration. A lament is eligible when it moves toward honest dependence; do not select despair in isolation if it misrepresents the psalm's arc. Call a verse messianic only when the New Testament applies it to Christ or its royal/redemptive meaning is clear. For imprecatory sections, apply Exclusion B and select the surrounding trust or plea for deliverance if it stands as a complete unit. Keep parallel lines together.

PROPHETS: Distinguish oracles of judgment (generally ineligible unless they carry a substantial lesson on sin, repentance, or God's character), calls to repentance, promises of restoration and the New Covenant, messianic prophecy, and revelations of God's character. Prefer calls to return to God, promises of mercy, a new heart and spirit, the coming Messiah. A promise addressed to Israel is selected for what it reveals about God or the New Covenant, not as a personal guarantee, without textual or New Testament support. Skip purely geopolitical or military content.

REVELATION AND APOCALYPTIC (Daniel, Ezekiel, Zechariah, Revelation): Treat imagery as imagery; do not literalize symbols or build timelines. Prefer worship, the character and victory of Christ, assurance, perseverance, promises to overcomers, and the renewal of all things. Avoid vivid destruction without a clear devotional lesson.

NARRATIVE AND LAW: In narrative, select the distinct episode with a textually supported lesson, including the response or consequence needed for context. In law, retain enduring moral and relational principles (justice, mercy, honesty, care for the poor); exclude ceremonial and covenant-specific material per Exclusion A.

ECCLESIASTES: Read within "under the sun." Do not present a deliberately limited observation as universal theology. Retain wisdom, reverence for God, responsible living, and the limits of earthly pursuits.

JOB: Distinguish faith, grief, protest, despair, repentance, longing. Do not treat every statement by Job or his friends as authoritative (see Job 42:7). Select trust, honest dependence, repentance, hope, longing for the Redeemer, and God's own speech about His character. Do not exclude a passage merely for expressing suffering.

PROVERBS: Treat each proverb as its own saying unless adjacent verses clearly form one thought. Do not combine unrelated aphorisms. Preserve qualifications and contrasts.

SONG OF SONGS: Eligible themes: faithful marital love, devotion, commitment, enduring affection. Avoid explicit anatomical description. Do not impose allegory without broader biblical support.

GOSPELS, PARABLES, ANTAGONIST SPEECH: Extract a parable's spiritual lesson, not unethical behavior to imitate; distinguish the main teaching from incidental details. Do not treat speech by Satan, demons, or opponents as authoritative doctrine. A narrative containing such speech may be eligible when the narrator or Jesus establishes a meaningful lesson.

SELECTION PROCEDURE

1. DISCOVER: list every potentially eligible passage in the chapter (commands, promises, prayers, teaching, doctrine, prophecy, faithful examples, repentance, significant episodes). Review the whole chapter, not just the obvious passage.
2. TEST: a candidate must satisfy ALL THREE: (i) TEXTUAL SUPPORT: the verses clearly support the proposed theme (reject invented lessons, speculation, misattributed speakers, misread behavior, unsupported theology); (ii) CONTEXTUAL INTEGRITY: it does not mislead when read alone; (iii) DEVOTIONAL VALUE: it substantially contributes to New Covenant spiritual growth. If any fails, exclude it.
3. APPLY EXCLUSIONS by meaning and function, not by the presence of a word, speaker, or genre. A negative event with a distinct, supported lesson on repentance, restoration, accountability, or mercy is evaluated on that lesson.
4. SET BOUNDARIES: choose the smallest naturally complete unit. Prefer 2-4 verses, but a single verse is fine if it is a complete thought, and longer is fine when shortening would fragment a teaching, parable, prayer, argument, or episode. Include necessary setup, qualification, or response. Do not combine unrelated statements. Avoid overlap unless each unit offers a genuinely different insight and is complete on its own.
5. FINAL CHECK: re-review the chapter for overlooked eligible passages (especially doctrinal), repeated teachings, passages excluded only for mentioning sin, suffering, judgment, or ceremony, passages included only because they sound inspirational, and inconsistent standards.

CATEGORIES

Assign exactly one category per passage, from this list only:
${CATEGORIES.join(', ')}

Choose the category matching the passage's central devotional function. Use "miracle" for supernatural healings and wonders, "parable" for Jesus' kingdom parables and comparable teachings, "repentance" when turning from sin to God is central. Do not choose a category just because a related word appears. Never invent a category or change its spelling.

THEME

A natural, descriptive title in Title Case, 3 to 6 words, describing the actual content. Prefer specific wording over devotional slogans. Do not overstate the passage's promise or add unsupported theology. Examples: "Jesus Calms the Wind and Waves", "The True Vine and Branches", "Love Your Enemies and Do Good", "A Prayer for a Clean Heart".

TAGS

Allowed tags (use these exact values only):
${MASTER_TAGS.join(', ')}

Choose 1 to 5 tags per passage, ranked from most to least relevant. Include a tag only when it directly and substantially applies. No duplicates, no filler, no remote associations. Prefer the most specific applicable tag over a broad one. Never invent or alter a tag.

OUTPUT FORMAT (JSON)

Return ONLY a valid JSON object, with no Markdown fences and no text outside it. It has exactly one key, "passages", an array. Each element has EXACTLY these fields:

{"startVerse": <integer>, "endVerse": <integer >= startVerse>, "category": "<one allowed category>", "theme": "<3-6 word Title Case title>", "tags": ["<1-5 unique allowed tags>"]}

If nothing qualifies, return {"passages": []}.

EXAMPLES (illustrating format and judgment only; verse numbers and values are illustrative and do not refer to your chapter)

Example 1 — a parable kept whole:
{"passages": [{"startVerse": 11, "endVerse": 24, "category": "parable", "theme": "The Father Welcomes the Returning Son", "tags": ["<tag>", "<tag>"]}]}

Example 2 — a sin episode where only the confession and mercy are selected, not the sin itself:
{"passages": [{"startVerse": 13, "endVerse": 14, "category": "repentance", "theme": "Confession and God's Forgiveness", "tags": ["<tag>", "<tag>"]}]}

Example 3 — a chapter of boundary lists or ceremonial regulations:
{"passages": []}
${prev ? `PRECEDING CONTEXT (read-only, do not select from this):\n${prev.book} ${prev.chapter}\n${prev.verses.map(v => `${v.verse}. ${v.text}`).join('\n')}\n\n` : ''}TARGET CHAPTER (select only from these verses):
${bookName} ${chapter} (World English Bible):

${verses.map(v => `${v.verse}. ${v.text}`).join('\n')}

${next ? `\nFOLLOWING CONTEXT (read-only, do not select from this):\n${next.book} ${next.chapter}\n${next.verses.map(v => `${v.verse}. ${v.text}`).join('\n')}\n` : ''}
FINAL CHECKLIST before you answer:
- Select only from the TARGET CHAPTER verses; never alter verse numbers.
- Exclude Old Covenant ceremonial and warfare/imprecation material per the firm exclusions.
- Keep arguments, parables, and episodes whole; do not combine unrelated verses.
- Do not present sin, or a quoted opponent's speech, as an example or doctrine.
- Use only allowed categories and tags; 1-5 unique tags, ranked.
- Theme: Title Case, 3-6 words.
- Quality over quantity: if nothing qualifies, return {"passages": []}.

Return the JSON object now.`;
}

async function callDeepSeekWithRetry(prompt, maxRetries = 5) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${API_KEY}`,
        },
        body: JSON.stringify({
          model: MODEL_ID,
          messages: [{ role: 'user', content: prompt }],
          temperature: 0.2,
        }),
      });

      if (!res.ok) {
        const errText = await res.text();
        if (res.status === 429 || res.status >= 500) {
          const delay = attempt * 3000;
          console.warn(`  [Retry ${attempt}/${maxRetries}] Status ${res.status}. Waiting ${delay / 1000}s...`);
          await new Promise(r => setTimeout(r, delay));
          continue;
        }
        throw new Error(`API Error [${res.status}]: ${errText}`);
      }

      const data = await res.json();
      const content = data.choices[0]?.message?.content || '';
      const usage = data.usage || {};
      return { content, usage };
    } catch (err) {
      if (attempt === maxRetries) throw err;
      const delay = attempt * 2500;
      console.warn(`  [Retry ${attempt}/${maxRetries}] Network error: ${err.message}. Retrying in ${delay / 1000}s...`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

function parseAndValidate(rawOutput, bookNum, bookName, chapter, verses) {
  const minVerse = Math.min(...verses.map(v => v.verse));
  const maxVerse = Math.max(...verses.map(v => v.verse));

  let items = null;
  const cleaned = rawOutput.trim();

  // 1. Try direct parse of entire text or markdown code fence
  let jsonString = cleaned;
  const codeMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (codeMatch) {
    jsonString = codeMatch[1].trim();
  }

  try {
    const parsed = JSON.parse(jsonString);
    if (parsed && Array.isArray(parsed.passages)) {
      items = parsed.passages;
    } else if (Array.isArray(parsed)) {
      items = parsed;
    }
  } catch (_) {}

  // 2. If not parsed yet, search for {"passages": [...]} object pattern
  if (items === null) {
    const objMatch = cleaned.match(/\{\s*"passages"\s*:\s*(\[\s*[\s\S]*?\])\s*\}/);
    if (objMatch) {
      try {
        items = JSON.parse(objMatch[1]);
      } catch (_) {}
    }
  }

  // 3. Fallback: check for naked JSON array [{...}] or empty array []
  if (items === null) {
    const arrayMatch = cleaned.match(/\[\s*\{[\s\S]*\}\s*\]/);
    if (arrayMatch) {
      try {
        items = JSON.parse(arrayMatch[0]);
      } catch (_) {}
    } else if (/\[\s*\]/.test(cleaned) || /"passages"\s*:\s*\[\s*\]/.test(cleaned)) {
      items = [];
    }
  }

  // 4. Fallback: slice between outermost brackets
  if (items === null) {
    const sIdx = cleaned.indexOf('[');
    const eIdx = cleaned.lastIndexOf(']');
    if (sIdx !== -1 && eIdx >= sIdx) {
      try {
        items = JSON.parse(cleaned.slice(sIdx, eIdx + 1));
      } catch (_) {
        items = [];
      }
    } else {
      items = [];
    }
  }

  if (!Array.isArray(items)) {
    throw new Error('LLM output could not be parsed as passages array: ' + cleaned.slice(0, 100));
  }

  const validRecords = [];
  let bgIdx = 0;

  for (const item of items) {
    const start = Number(item.startVerse);
    const end = Number(item.endVerse || start);

    if (isNaN(start) || start < minVerse || start > maxVerse) continue;
    if (isNaN(end) || end < start || end > maxVerse) continue;
    if (end - start > 30) continue; // safety guard against whole-chapter dumps

    let category = String(item.category || '').toLowerCase().trim().replace(/\s+/g, '_');
    if (!CATEGORIES.includes(category)) {
      category = 'doctrine';
    }

    const theme = String(item.theme || '').trim().replace(/^["']|["']$/g, '').slice(0, 100);

    // Validate and sanitize top-5 tags
    let tags = [];
    if (Array.isArray(item.tags)) {
      for (const t of item.tags) {
        const clean = String(t).toLowerCase().trim().replace(/\s+/g, '_');
        if (MASTER_TAGS.includes(clean) && !tags.includes(clean)) {
          tags.push(clean);
        }
      }
    }
    // Ensure at least 1 tag, and at most 5
    if (tags.length === 0) {
      tags = [category.replace(/s$/, '') || 'faith'];
    }
    tags = tags.slice(0, 5);

    const label = start === end
      ? `${bookName} ${chapter}:${start}`
      : `${bookName} ${chapter}:${start}-${end}`;

    const bgPreset = BG_PRESETS[bgIdx % BG_PRESETS.length];
    bgIdx++;

    validRecords.push({
      engine: 'scripture',
      bookNumber: bookNum,
      bookName: bookName,
      chapter: chapter,
      startVerse: start,
      endVerse: end,
      referenceLabel: label,
      verseMappings: {},
      category: category,
      theme: theme || label,
      tags: tags,
      backgroundPreset: bgPreset,
      isFeatured: false,
    });
  }

  return validRecords;
}

// ---------------------------------------------------------------------------
// Compilation & SQLite Generation Pipeline
// ---------------------------------------------------------------------------
function compileAll() {
  console.log('\n' + '='.repeat(70));
  console.log(' COMPILING FINAL SCRIPTURES DATASET, SQLITE, AND WORDS FEED');
  console.log('='.repeat(70));

  ensureDirs();
  const files = fs.readdirSync(CHAPTERS_CACHE_DIR).filter(f => f.endsWith('.json'));
  if (files.length === 0) {
    throw new Error('No cached chapters found in ' + CHAPTERS_CACHE_DIR);
  }

  console.log(`Reading ${files.length} cached chapter files...`);

  const allRecords = [];
  const sortedFiles = files.sort((a, b) => {
    const ma = a.match(/b(\d+)_c(\d+)/);
    const mb = b.match(/b(\d+)_c(\d+)/);
    if (!ma || !mb) return a.localeCompare(b);
    const bA = parseInt(ma[1], 10);
    const bB = parseInt(mb[1], 10);
    if (bA !== bB) return bA - bB;
    return parseInt(ma[2], 10) - parseInt(mb[2], 10);
  });

  for (const file of sortedFiles) {
    const filePath = path.join(CHAPTERS_CACHE_DIR, file);
    try {
      const records = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      if (Array.isArray(records)) {
        allRecords.push(...records);
      }
    } catch (e) {
      console.warn(`  Warning: Skipping invalid file ${file}: ${e.message}`);
    }
  }

  // Sort deterministically: bookNumber -> chapter -> startVerse
  allRecords.sort((a, b) => a.bookNumber - b.bookNumber || a.chapter - b.chapter || a.startVerse - b.startVerse);

  console.log(`✓ Total unique devotional passages: ${allRecords.length}`);

  // 1. Write scriptures_compiled.json cache
  fs.writeFileSync(COMPILED_FILE, JSON.stringify(allRecords, null, 2), 'utf8');
  console.log(`✓ Saved compiled cache: ${COMPILED_FILE}`);

  // 2. Emit canonical scriptures.json
  fs.writeFileSync(CANONICAL_SCRIPTURES, JSON.stringify(allRecords, null, 2), 'utf8');
  console.log(`✓ Emitted canonical scriptures.json: ${CANONICAL_SCRIPTURES} (${(fs.statSync(CANONICAL_SCRIPTURES).size / (1024 * 1024)).toFixed(2)} MB)`);

  // Mirror to backend data if present
  if (fs.existsSync(path.dirname(BACKEND_SCRIPTURES))) {
    fs.writeFileSync(BACKEND_SCRIPTURES, JSON.stringify(allRecords, null, 2), 'utf8');
    console.log(`✓ Mirrored to backend: ${BACKEND_SCRIPTURES}`);
  }

  // 3. Build SQLite Database with FTS5 Full-Text Search
  console.log('\n--- Building SQLite Feed Database (releases/scriptures.sqlite) ---');
  if (fs.existsSync(SQLITE_OUT)) {
    try { fs.unlinkSync(SQLITE_OUT); } catch (_) {}
  }

  const db = new DatabaseSync(SQLITE_OUT);

  db.exec(`
    CREATE TABLE feed (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      engine TEXT NOT NULL,
      bookNumber INTEGER NOT NULL,
      bookName TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      startVerse INTEGER NOT NULL,
      endVerse INTEGER NOT NULL,
      referenceLabel TEXT NOT NULL,
      category TEXT NOT NULL,
      theme TEXT NOT NULL,
      backgroundPreset TEXT NOT NULL,
      tags TEXT NOT NULL,
      isFeatured INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX idx_feed_book_name ON feed(bookName);
    CREATE INDEX idx_feed_book_number ON feed(bookNumber);
    CREATE INDEX idx_feed_category ON feed(category);
    CREATE INDEX idx_feed_book_chap ON feed(bookNumber, chapter);

    CREATE VIRTUAL TABLE feed_fts USING fts5(
      referenceLabel,
      category,
      theme,
      tags,
      content='feed',
      content_rowid='id'
    );
  `);

  const insert = db.prepare(`
    INSERT INTO feed (
      engine, bookNumber, bookName, chapter, startVerse, endVerse,
      referenceLabel, category, theme, backgroundPreset, tags, isFeatured
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  db.exec('BEGIN TRANSACTION');
  for (const r of allRecords) {
    insert.run(
      r.engine,
      r.bookNumber,
      r.bookName,
      r.chapter,
      r.startVerse,
      r.endVerse,
      r.referenceLabel,
      r.category,
      r.theme,
      r.backgroundPreset,
      JSON.stringify(r.tags),
      r.isFeatured ? 1 : 0
    );
  }
  db.exec('COMMIT');

  // Populate FTS5 index
  db.exec(`
    INSERT INTO feed_fts(rowid, referenceLabel, category, theme, tags)
    SELECT id, referenceLabel, category, theme, tags FROM feed;
  `);

  db.close();
  const dbBytes = fs.statSync(SQLITE_OUT).size;
  console.log(`✓ Built SQLite database: ${(dbBytes / (1024 * 1024)).toFixed(2)} MB`);

  // Compress to .sqlite.gz
  const gzBytes = zlib.gzipSync(fs.readFileSync(SQLITE_OUT), { level: 9 });
  fs.writeFileSync(SQLITE_GZ_OUT, gzBytes);
  console.log(`✓ Compressed scriptures.sqlite.gz: ${(gzBytes.length / (1024 * 1024)).toFixed(2)} MB`);

  // 4. Chunk Words Feed
  chunkWordsFeed(allRecords);

  // 5. Bump Revision in manifest.json
  bumpRevision();

  console.log('\n' + '='.repeat(70));
  console.log(' ALL ASSETS GENERATED & SYNCHRONIZED SUCCESSFULLY!');
  console.log('='.repeat(70));
}

function chunkWordsFeed(allRecords) {
  console.log('\n--- Chunking Words Feed (releases/words_feed/) ---');
  if (!fs.existsSync(WORDS_FEED_DIR)) {
    fs.mkdirSync(WORDS_FEED_DIR, { recursive: true });
  }
  const byLetterDir = path.join(WORDS_FEED_DIR, 'by_letter');
  const topicsDir = path.join(WORDS_FEED_DIR, 'topics');

  // Clean out stale files in by_letter and topics
  if (fs.existsSync(byLetterDir)) fs.rmSync(byLetterDir, { recursive: true, force: true });
  if (fs.existsSync(topicsDir)) fs.rmSync(topicsDir, { recursive: true, force: true });

  fs.mkdirSync(byLetterDir, { recursive: true });
  fs.mkdirSync(topicsDir, { recursive: true });

  // Top 365 daily devotionals
  const daily = allRecords.slice(0, 365).map((item, idx) => ({
    dayOfYear: idx + 1,
    bookNumber: item.bookNumber,
    bookName: item.bookName,
    chapter: item.chapter,
    startVerse: item.startVerse,
    endVerse: item.endVerse,
    referenceLabel: item.referenceLabel,
    category: item.category,
    theme: item.theme,
    backgroundPreset: item.backgroundPreset || 'ocean_calm',
    tags: item.tags,
  }));
  fs.writeFileSync(path.join(WORDS_FEED_DIR, 'daily.json'), JSON.stringify(daily, null, 2), 'utf8');

  // Shard by topic and letter
  const letterMap = new Map();
  const topicMap = new Map();

  for (const item of allRecords) {
    // Primary topic is top-ranked tag or category
    const primaryTopic = (item.tags && item.tags[0]) || item.category || 'faith';
    const slug = primaryTopic.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    const letter = (slug[0] || 'a').toLowerCase();

    if (!letterMap.has(letter)) letterMap.set(letter, []);
    letterMap.get(letter).push(item);

    if (!topicMap.has(slug)) {
      topicMap.set(slug, { name: primaryTopic.replace(/_/g, ' '), items: [] });
    }
    topicMap.get(slug).items.push(item);
  }

  for (const [letter, items] of letterMap.entries()) {
    fs.writeFileSync(path.join(byLetterDir, `${letter}.json`), JSON.stringify(items, null, 2), 'utf8');
  }

  const sortedTopics = Array.from(topicMap.entries())
    .map(([slug, data]) => ({ slug, name: data.name, count: data.items.length, items: data.items }))
    .sort((a, b) => b.count - a.count);

  for (const t of sortedTopics) {
    fs.writeFileSync(path.join(topicsDir, `${t.slug}.json`), JSON.stringify(t.items, null, 2), 'utf8');
  }

  fs.writeFileSync(path.join(WORDS_FEED_DIR, 'manifest.json'), JSON.stringify({
    totalItems: allRecords.length,
    letters: Array.from(letterMap.keys()).sort(),
    topTopics: sortedTopics.map(t => ({ slug: t.slug, name: t.name, count: t.count })),
    updatedAt: new Date().toISOString(),
  }, null, 2), 'utf8');

  console.log(`✓ Words feed chunked: daily.json (365), ${letterMap.size} letters, ${sortedTopics.length} topic files.`);
}

function bumpRevision() {
  console.log('\n--- Updating manifest.json Revision ---');
  let manifest = { revision: 'v1.0.0', updatedAt: new Date().toISOString() };
  if (fs.existsSync(MANIFEST_FILE)) {
    try {
      manifest = JSON.parse(fs.readFileSync(MANIFEST_FILE, 'utf8'));
    } catch (_) {}
  }
  const newRev = Math.random().toString(36).slice(2, 10);
  manifest.revision = newRev;
  manifest.updatedAt = new Date().toISOString();
  fs.writeFileSync(MANIFEST_FILE, JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`✓ Bumper dataset revision to: ${newRev}`);
}

// ---------------------------------------------------------------------------
// Processing Engine with Auto-Recovery
// ---------------------------------------------------------------------------
async function processAllChapters(options = {}) {
  ensureDirs();
  const books = loadBooks();
  const status = loadStatus();

  const total = 1189;
  const limit = options.limit !== undefined ? options.limit : Infinity;
  let processedThisRun = 0;

  console.log('\n' + '='.repeat(70));
  console.log(` DEEPSEEK-V3 DEVOTIONAL SCRIPTURE EXTRACTION`);
  console.log('='.repeat(70));
  console.log(`Model:             ${MODEL_ID}`);
  console.log(`Source Bible:      World English Bible (releases/bibles/web/)`);
  console.log(`Total Chapters:    ${total}`);
  console.log(`Already Completed: ${Object.keys(status.completed).length} / ${total}`);
  console.log(`Target Limit:      ${limit === Infinity ? 'All remaining' : limit}`);
  console.log('='.repeat(70) + '\n');

  for (const [bookIndex, book] of books.entries()) {
    if (options.targetBook && book.bookNumber !== options.targetBook) continue;

    for (let c = 1; c <= book.chapters; c++) {
      if (options.targetChapter && c !== options.targetChapter) continue;

      if (processedThisRun >= limit) {
        console.log(`\nReached target limit of ${limit} chapters. Halting.`);
        printStatus(status);
        return;
      }

      const key = `b${book.bookNumber}_c${c}`;
      const cachePath = path.join(CHAPTERS_CACHE_DIR, `${key}.json`);

      // Resume check: if already completed and cache file exists, skip
      if (!options.redo && fs.existsSync(cachePath) && status.completed[key]) {
        continue;
      }

      const completedCount = Object.keys(status.completed).length;
      const startTime = Date.now();
      process.stdout.write(`[${completedCount + 1}/${total}] ${book.name} ${c}... `);

      try {
        const verses = loadChapterVerses(book.bookNumber, c);
        const { prev, next } = getNeighborContext(books, bookIndex, c);
        const prompt = buildPrompt(book.name, c, verses, prev, next);
        const { content, usage } = await callDeepSeekWithRetry(prompt);
        const records = parseAndValidate(content, book.bookNumber, book.name, c, verses);

        fs.writeFileSync(cachePath, JSON.stringify(records, null, 2), 'utf8');

        // Usage and billing calculation
        const pTokens = usage.prompt_tokens || 0;
        const cTokens = usage.completion_tokens || 0;
        const callCostUSD = (pTokens / 1_000_000) * 0.27 + (cTokens / 1_000_000) * 1.10;

        status.completed[key] = {
          count: records.length,
          timestamp: new Date().toISOString(),
        };
        delete status.failed[key];

        status.totalTokens = (status.totalTokens || 0) + (usage.total_tokens || 0);
        status.totalCostUSD = (status.totalCostUSD || 0) + callCostUSD;
        status.totalPassagesExtracted = Object.values(status.completed).reduce(
          (acc, cur) => acc + (cur.count || 0), 0
        );

        saveStatus(status);

        const duration = ((Date.now() - startTime) / 1000).toFixed(1);
        console.log(`✓ ${records.length} passages (${duration}s)`);
        processedThisRun++;

        // Polite micro-delay
        await new Promise(r => setTimeout(r, 100));
      } catch (err) {
        console.log(`✗ Error: ${err.message}`);
        status.failed[key] = {
          error: err.message,
          timestamp: new Date().toISOString(),
        };
        saveStatus(status);
        await new Promise(r => setTimeout(r, 1500));
      }
    }
  }

  // Auto-Recovery Sweep: Retry any chapters that failed during the run
  const failedKeys = Object.keys(status.failed);
  if (failedKeys.length > 0 && limit === Infinity) {
    console.log(`\n--- Auto-Recovery Sweep: Retrying ${failedKeys.length} failed chapters ---`);
    for (const key of failedKeys) {
      const m = key.match(/^b(\d+)_c(\d+)$/);
      if (!m) continue;
      const bNum = parseInt(m[1], 10);
      const chap = parseInt(m[2], 10);
      const bIndex = books.findIndex(b => b.bookNumber === bNum);
      const bookObj = bIndex !== -1 ? books[bIndex] : null;
      const bName = bookObj ? bookObj.name : `Book ${bNum}`;

      process.stdout.write(`[Recovery] ${bName} ${chap}... `);
      try {
        const verses = loadChapterVerses(bNum, chap);
        const { prev, next } = getNeighborContext(books, bIndex, chap);
        const prompt = buildPrompt(bName, chap, verses, prev, next);
        const { content, usage } = await callDeepSeekWithRetry(prompt);
        const records = parseAndValidate(content, bNum, bName, chap, verses);

        const cachePath = path.join(CHAPTERS_CACHE_DIR, `${key}.json`);
        fs.writeFileSync(cachePath, JSON.stringify(records, null, 2), 'utf8');

        status.completed[key] = { count: records.length, timestamp: new Date().toISOString() };
        delete status.failed[key];
        saveStatus(status);
        console.log(`✓ Recovered (${records.length} passages)`);
      } catch (e) {
        console.log(`✗ Still failed: ${e.message}`);
      }
    }
  }

  printStatus(status);

  // Check if ALL chapters are complete. If so, automatically compile and generate SQLite!
  const finalCompleted = Object.keys(status.completed).length;
  if (finalCompleted >= total) {
    console.log('\n🎉 ALL 1,189 CHAPTERS COMPLETED! Launching automatic compilation...');
    compileAll();
  }
}

function printStatus(status) {
  const completedKeys = Object.keys(status.completed);
  const failedKeys = Object.keys(status.failed);
  const total = 1189;
  const pct = ((completedKeys.length / total) * 100).toFixed(1);
  const inr = (status.totalCostUSD * 87.0).toFixed(2);

  console.log('\n' + '='.repeat(65));
  console.log(' DEEPSEEK SCRIPTURES STATUS SUMMARY');
  console.log('='.repeat(65));
  console.log(`Completed Chapters:        ${completedKeys.length} / ${total} (${pct}%)`);
  console.log(`Failed Chapters:           ${failedKeys.length}`);
  console.log(`Remaining Chapters:        ${total - completedKeys.length}`);
  console.log(`Total Passages Extracted:  ${status.totalPassagesExtracted}`);
  console.log(`Total Tokens:              ${(status.totalTokens || 0).toLocaleString()}`);
  console.log(`Estimated Cost:            $${status.totalCostUSD.toFixed(4)} (~₹${inr})`);
  console.log(`Last Updated:              ${status.lastRunAt || 'Never'}`);
  console.log('='.repeat(65));
}

// ---------------------------------------------------------------------------
// Self-Testing Suite (--test)
// ---------------------------------------------------------------------------
async function runSelfTest() {
  console.log('================================================================');
  console.log(' RUNNING END-TO-END PRE-FLIGHT VERIFICATION TEST');
  console.log('================================================================\n');

  // 1. Verify DeepSeek API connectivity and prompt schema with Genesis 1
  console.log('Test 1: Testing DeepSeek-V3 API call & Schema validation on Genesis 1...');
  const books = loadBooks();
  const verses = loadChapterVerses(1, 1);
  const { prev, next } = getNeighborContext(books, 0, 1);
  const prompt = buildPrompt('Genesis', 1, verses.slice(0, 5), prev, next);
  const { content, usage } = await callDeepSeekWithRetry(prompt, 2);
  const records = parseAndValidate(content, 1, 'Genesis', 1, verses);

  if (records.length === 0) {
    throw new Error('Test 1 Failed: No records parsed from test prompt');
  }
  const sample = records[0];
  console.log(`  ✓ API returned valid response in usage: ${usage.total_tokens} tokens`);
  console.log(`  ✓ Sample Record: ${sample.referenceLabel} | Category: ${sample.category} | Theme: "${sample.theme}"`);
  console.log(`  ✓ Top-5 Tags: ${sample.tags.join(', ')}`);

  // Verify tags are strictly from MASTER_TAGS
  for (const t of sample.tags) {
    if (!MASTER_TAGS.includes(t)) {
      throw new Error(`Test 1 Failed: Tag "${t}" not found in MASTER_TAGS`);
    }
  }
  console.log('  ✓ Tag vocabulary validation passed.');

  // 2. Test SQLite and FTS5 creation
  console.log('\nTest 2: Testing SQLite creation and FTS5 indexing...');
  ensureDirs();
  const testDbPath = path.join(CACHE_DIR, 'test_scriptures.sqlite');
  if (fs.existsSync(testDbPath)) fs.unlinkSync(testDbPath);

  const testDb = new DatabaseSync(testDbPath);
  testDb.exec(`
    CREATE TABLE feed (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      engine TEXT NOT NULL,
      bookNumber INTEGER NOT NULL,
      bookName TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      startVerse INTEGER NOT NULL,
      endVerse INTEGER NOT NULL,
      referenceLabel TEXT NOT NULL,
      category TEXT NOT NULL,
      theme TEXT NOT NULL,
      backgroundPreset TEXT NOT NULL,
      tags TEXT NOT NULL,
      isFeatured INTEGER NOT NULL DEFAULT 0
    );
    CREATE VIRTUAL TABLE feed_fts USING fts5(
      referenceLabel,
      category,
      theme,
      tags,
      content='feed',
      content_rowid='id'
    );
  `);

  const ins = testDb.prepare(`
    INSERT INTO feed (engine, bookNumber, bookName, chapter, startVerse, endVerse, referenceLabel, category, theme, backgroundPreset, tags, isFeatured)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  ins.run(sample.engine, sample.bookNumber, sample.bookName, sample.chapter, sample.startVerse, sample.endVerse, sample.referenceLabel, sample.category, sample.theme, sample.backgroundPreset, JSON.stringify(sample.tags), 0);

  testDb.exec(`
    INSERT INTO feed_fts(rowid, referenceLabel, category, theme, tags)
    SELECT id, referenceLabel, category, theme, tags FROM feed;
  `);

  const query = testDb.prepare('SELECT COUNT(*) as count FROM feed').get();
  if (query.count !== 1) {
    throw new Error('Test 2 Failed: SQLite row count mismatch');
  }

  const ftsQuery = testDb.prepare('SELECT rowid, referenceLabel FROM feed_fts WHERE feed_fts MATCH ?').all(sample.category);
  if (ftsQuery.length === 0) {
    throw new Error('Test 2 Failed: FTS5 query returned no results');
  }
  testDb.close();
  console.log('  ✓ SQLite creation and FTS5 query verified successfully.');

  // 3. Test Gzip Compression
  console.log('\nTest 3: Testing Gzip compression...');
  const gz = zlib.gzipSync(fs.readFileSync(testDbPath));
  console.log(`  ✓ Compressed SQLite DB size: ${gz.length} bytes.`);
  fs.unlinkSync(testDbPath);

  // 4. Test Book list coverage
  console.log('\nTest 4: Verifying Bible chapter completeness...');
  let chapCount = 0;
  for (const b of books) {
    chapCount += b.chapters;
  }
  if (chapCount !== 1189) {
    throw new Error(`Test 4 Failed: Expected 1189 chapters, found ${chapCount}`);
  }
  console.log(`  ✓ All ${books.length} books and ${chapCount} chapters verified.`);

  console.log('\n================================================================');
  console.log(' ALL 4 PRE-FLIGHT TESTS PASSED CLEANLY! Ready for production.');
  console.log('================================================================\n');
}

// ---------------------------------------------------------------------------
// CLI Dispatcher
// ---------------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);
  const options = {
    limit: undefined,
    targetBook: undefined,
    targetChapter: undefined,
    redo: false,
  };

  const status = loadStatus();

  if (args.includes('--test')) {
    await runSelfTest();
    return;
  }

  if (args.includes('--status')) {
    printStatus(status);
    return;
  }

  if (args.includes('--compile')) {
    compileAll();
    return;
  }

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--limit') {
      options.limit = parseInt(args[++i], 10);
    } else if (args[i] === '--book') {
      options.targetBook = parseInt(args[++i], 10);
    } else if (args[i] === '--chapter') {
      options.targetChapter = parseInt(args[++i], 10);
    } else if (args[i] === '--redo') {
      options.redo = true;
    } else if (args[i] === '--all') {
      options.limit = Infinity;
    }
  }

  if (options.limit === undefined && !options.targetBook && !options.targetChapter) {
    options.limit = Infinity;
  }

  await processAllChapters(options);
}

main().catch(err => {
  console.error('\nFatal execution error:', err);
  process.exit(1);
});
