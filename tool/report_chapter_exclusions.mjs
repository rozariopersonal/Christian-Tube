#!/usr/bin/env node
/**
 * tool/report_chapter_exclusions.mjs
 * 
 * Sequentially identifies already existing/extracted words appearing in each chapter.
 * Accurately matches ONLY words that are present in the current chapter's verses.
 * 
 * Each word pair is output on a NEW LINE with a LINE NUMBER:
 * 1. "token_in_verse" ➔ Existing Word [Origin Chapter]
 * 
 * Usage:
 *   node tool/report_chapter_exclusions.mjs --book 1             # Genesis only
 *   node tool/report_chapter_exclusions.mjs --limit 10           # First 10 chapters
 *   node tool/report_chapter_exclusions.mjs --all                # All cached chapters
 *   node tool/report_chapter_exclusions.mjs --out report.md      # Save to custom file
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

const BIBLE_DIR = path.join(ROOT, 'releases', 'bibles', 'taobvsi');
const BOOKS_FILE = path.join(BIBLE_DIR, 'books.json');
const CHAPTERS_CACHE_DIR = path.join(ROOT, '.cache', 'glossary_deepseek', 'chapters');

const TAMIL_BOOK_NAMES = {
  1: "ஆதியாகமம் (Genesis)",
  2: "யாத்திராகமம் (Exodus)",
  3: "லேவியராகமம் (Leviticus)",
  4: "எண்ணாகமம் (Numbers)",
  5: "உபாகமம் (Deuteronomy)",
  6: "யோசுவா (Joshua)",
  7: "நியாயாதிபதிகள் (Judges)",
  8: "ரூத் (Ruth)",
  9: "1 சாமுவேல் (1 Samuel)",
  10: "2 சாமுவேல் (2 Samuel)",
  11: "1 இராஜாக்கள் (1 Kings)",
  12: "2 இராஜாக்கள் (2 Kings)",
  13: "1 நாளாகமம் (1 Chronicles)",
  14: "2 நாளாகமம் (2 Chronicles)",
  15: "எஸ்றா (Ezra)",
  16: "நெகேமியா (Nehemiah)",
  17: "எஸ்தர் (Esther)",
  18: "யோபு (Job)",
  19: "சங்கீதம் (Psalms)",
  20: "நீதிமொழிகள் (Proverbs)",
  21: "பிரசங்கி (Ecclesiastes)",
  22: "உன்னதப்பாட்டு (Song of Solomon)",
  23: "ஏசாயா (Isaiah)",
  24: "எரேமியா (Jeremiah)",
  25: "புலம்பல் (Lamentations)",
  26: "எசேக்கியேல் (Ezekiel)",
  27: "தானியேல் (Daniel)",
  28: "ஓசியா (Hosea)",
  29: "யோவேல் (Joel)",
  30: "ஆமோஸ் (Amos)",
  31: "ஒபதியா (Obadiah)",
  32: "யோனா (Jonah)",
  33: "மீகா (Micah)",
  34: "நாகூம் (Nahum)",
  35: "அபகூக் (Habakkuk)",
  36: "செப்பனியா (Zephaniah)",
  37: "ஆகாய் (Haggai)",
  38: "சகரியா (Zechariah)",
  39: "மல்கியா (Malachi)",
  40: "மத்தேயு (Matthew)",
  41: "மாற்கு (Mark)",
  42: "லூக்கா (Luke)",
  43: "யோவான் (John)",
  44: "அப்போஸ்தலர் (Acts)",
  45: "ரோமர் (Romans)",
  46: "1 கொரிந்தியர் (1 Corinthians)",
  47: "2 கொரிந்தியர் (2 Corinthians)",
  48: "கலாத்தியர் (Galatians)",
  49: "எபேசியர் (Ephesians)",
  50: "பிலிப்பியர் (Philippians)",
  51: "கொலோசெயர் (Colossians)",
  52: "1 தெசலோனிக்கேயர் (1 Thess)",
  53: "2 தெசலோனிக்கேயர் (2 Thess)",
  54: "1 தீமோத்தேயு (1 Timothy)",
  55: "2 தீமோத்தேயு (2 Timothy)",
  56: "தீத்து (Titus)",
  57: "பிலேமோன் (Philemon)",
  58: "எபிரெயர் (Hebrews)",
  59: "யாக்கோபு (James)",
  60: "1 பேதுரு (1 Peter)",
  61: "2 பேதுரு (2 Peter)",
  62: "1 யோவான் (1 John)",
  63: "2 யோவான் (2 John)",
  64: "3 யோவான் (3 John)",
  65: "யூதா (Jude)",
  66: "வெளிப்படுத்தின விசேஷம் (Revelation)"
};

/**
 * Extracts high-precision morphological stems for Tamil words.
 * Single-syllable / short words (length < 6 in UTF-16) NEVER have their endings stripped
 * to avoid wildcard prefix collisions (e.g. 'புல்' -> 'பு', 'வில்' -> 'வி', 'காம்' -> 'கா').
 */
function getTamilStems(hw) {
  const stems = new Set();

  // Strip noun endings ONLY if the resulting base stem has at least 2 syllables (UTF-16 length >= 3)
  // Only ம் (which changes to த்த / ம) and ன் (which changes to ன / ர) drop in Tamil declension.
  // ல், ள், ர் do NOT drop in Tamil grammar (e.g. இருள் + இல் = இருளில்; பதில் + ஐ = பதிலை).
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

class SequentialTracker {
  constructor() {
    this.knownHeadwords = new Set();
    this.formToHeadword = new Map();
    this.headwordStemsMap = new Map();
    this.headwordOriginMap = new Map(); // hw -> "Genesis 1"
  }

  registerEntries(entries, originLabel) {
    for (const e of entries) {
      if (!e.headword) continue;
      const hw = e.headword.trim();
      if (!this.headwordOriginMap.has(hw)) {
        this.headwordOriginMap.set(hw, originLabel);
      }
      this.knownHeadwords.add(hw);
      this.formToHeadword.set(hw, hw);
      (e.forms || []).forEach(f => this.formToHeadword.set(f.trim(), hw));
      const stems = getTamilStems(hw);
      for (const s of stems) {
        this.headwordStemsMap.set(s, hw);
      }
    }
  }

  getDetailedOverlaps(verses) {
    const text = verses.map(v => v.text).join(' ');
    const tokens = Array.from(new Set(
      text.replace(/[^\u0B80-\u0BFF\s]/g, ' ')
        .split(/\s+/)
        .map(t => t.trim())
        .filter(t => t.length > 0)
    ));

    const headwordGroupMap = new Map(); // hw -> { headword, origin, tokens: Set() }

    for (const token of tokens) {
      let matchedHw = null;

      // 1. Exact surface form match from previous extractions
      if (this.formToHeadword.has(token)) {
        matchedHw = this.formToHeadword.get(token);
      }
      // 2. Exact lemma match
      else if (this.knownHeadwords.has(token)) {
        matchedHw = token;
      }
      // 3. Multi-syllable stem prefix match (stem must have at least 2 full Tamil syllables: length >= 3)
      else {
        for (const [stem, hw] of this.headwordStemsMap.entries()) {
          if (stem.length >= 3 && token.startsWith(stem) && token.length <= stem.length + 15) {
            matchedHw = hw;
            break;
          }
        }
      }

      if (matchedHw) {
        const origin = this.headwordOriginMap.get(matchedHw) || 'previous chapter';
        if (!headwordGroupMap.has(matchedHw)) {
          headwordGroupMap.set(matchedHw, {
            headword: matchedHw,
            origin,
            tokens: new Set()
          });
        }
        headwordGroupMap.get(matchedHw).tokens.add(token);
      }
    }

    const headwordsList = Array.from(headwordGroupMap.values())
      .sort((a, b) => a.headword.localeCompare(b.headword, 'ta'));

    return headwordsList;
  }
}

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    book: null,
    limit: null,
    all: false,
    out: null
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--book' && args[i + 1]) {
      options.book = parseInt(args[++i], 10);
    } else if (args[i] === '--limit' && args[i + 1]) {
      options.limit = parseInt(args[++i], 10);
    } else if (args[i] === '--all') {
      options.all = true;
    } else if (args[i] === '--out' && args[i + 1]) {
      options.out = args[++i];
    }
  }

  // Default: if no options given, run Book 1 (Genesis)
  if (!options.book && !options.limit && !options.all) {
    options.book = 1;
  }

  return options;
}

async function main() {
  const options = parseArgs();
  const booksMeta = JSON.parse(fs.readFileSync(BOOKS_FILE, 'utf8'));

  // Build the list of chapters to process
  let chaptersToRun = [];
  for (const b of booksMeta) {
    if (options.book && b.bookNumber !== options.book) continue;
    for (let c = 1; c <= b.chapters; c++) {
      const key = `b${String(b.bookNumber).padStart(2, '0')}_c${String(c).padStart(3, '0')}`;
      chaptersToRun.push({
        b: b.bookNumber,
        c,
        key,
        bookName: TAMIL_BOOK_NAMES[b.bookNumber] || b.name,
        shortName: b.name
      });
    }
  }

  if (options.limit && chaptersToRun.length > options.limit) {
    chaptersToRun = chaptersToRun.slice(0, options.limit);
  }

  console.log(`\n=== SEQUENTIAL CHAPTER EXCLUSION MAPPER ===`);
  console.log(`Analyzing ${chaptersToRun.length} chapters sequentially...\n`);

  const tracker = new SequentialTracker();
  const reportData = [];

  for (const ch of chaptersToRun) {
    const versePath = path.join(BIBLE_DIR, String(ch.b), `${ch.c}.json`);
    if (!fs.existsSync(versePath)) {
      continue;
    }

    const verses = JSON.parse(fs.readFileSync(versePath, 'utf8'));

    // 1. Identify which existing words triggered exclusions in this chapter
    const headwordsList = tracker.getDetailedOverlaps(verses);

    reportData.push({
      book: ch.bookName,
      chapter: ch.c,
      count: headwordsList.length,
      headwordsList
    });

    // 2. Read this chapter's extracted entries from cache and register them
    const cacheFile = path.join(CHAPTERS_CACHE_DIR, `${ch.key}.json`);
    if (fs.existsSync(cacheFile)) {
      try {
        const cachedEntries = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
        const originLabel = `${ch.shortName} ${ch.c}`;
        tracker.registerEntries(cachedEntries, originLabel);
      } catch (e) {}
    }
  }

  // Generate Comprehensive Markdown Report
  const mdLines = [];
  mdLines.push(`# Sequential Chapter Exclusions & Provenance Map`);
  mdLines.push(`*Generated on: ${new Date().toISOString()}*`);
  mdLines.push(`*Total Chapters Analyzed: ${reportData.length}*`);
  mdLines.push(`*Total Unique Vocabulary Cataloged: ${tracker.knownHeadwords.size} lemmas*\n`);

  mdLines.push(`## 1. Master Table: Chapter Excluded Words & Origin Map\n`);
  mdLines.push(`| Book | Chapter | Excluded Count | Exclusion Map (Line Numbered: Word in Chapter ➔ Existing Catalog Word [Origin]) |`);
  mdLines.push(`| :--- | :---: | :---: | :--- |`);

  for (const r of reportData) {
    if (r.headwordsList.length === 0) {
      mdLines.push(`| ${r.book} | ${r.chapter} | **0** | *(None - First Chapter of Corpus)* |`);
      continue;
    }

    // Format map items: Each on a NEW LINE with LINE NUMBER
    const mapItems = r.headwordsList.map((item, idx) => {
      const sampleTokens = Array.from(item.tokens).slice(0, 3).map(t => `"${t}"`).join(', ');
      return `${idx + 1}. ${sampleTokens} ➔ **${item.headword}** [${item.origin}]`;
    });

    // In markdown table cells, join with <br> to show each item on a new line
    const tableCellContent = mapItems.join('<br>');
    mdLines.push(`| ${r.book} | ${r.chapter} | **${r.count}** | ${tableCellContent} |`);
  }

  mdLines.push(`\n---\n`);
  mdLines.push(`## 2. Detailed Per-Chapter Breakdown (Numbered Line by Line)\n`);

  for (const r of reportData) {
    if (r.headwordsList.length === 0) continue;

    mdLines.push(`### ${r.book} Chapter ${r.chapter} (${r.count} Excluded Words)`);
    r.headwordsList.forEach((hwItem, idx) => {
      const tokensStr = Array.from(hwItem.tokens).map(t => `\`"${t}"\``).join(', ');
      mdLines.push(`${idx + 1}. ${tokensStr} ➔ **${hwItem.headword}** (First cataloged in: *${hwItem.origin}*)`);
    });
    mdLines.push('');
  }

  const markdownContent = mdLines.join('\n');

  // Print table to stdout
  console.log(markdownContent);

  // Save report
  const outPath = options.out 
    ? path.resolve(process.cwd(), options.out)
    : path.join(ROOT, '.cache', 'glossary_deepseek', 'chapter_exclusions_report.md');

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, markdownContent, 'utf8');
  console.log(`\nReport successfully saved to: ${outPath}\n`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
