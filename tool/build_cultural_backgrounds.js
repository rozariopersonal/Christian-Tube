#!/usr/bin/env node
/**
 * build_cultural_backgrounds.js
 *
 * Fetches the unfoldingWord `en_tn` dataset (CC-BY-SA 4.0) from Door43,
 * filters and cleans historical, cultural, geographical, and custom notes
 * (excluding translator instructions and grammatical suggestions), and compiles
 * them into a compact, structured JSON format for the Bible reader.
 *
 * Usage:
 *   node tool/build_cultural_backgrounds.js [--sample] [output.json]
 *
 * Flags:
 *   --sample   Downloads only Genesis (GEN) and Matthew (MAT) for fast testing.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const BASE_URL = 'https://git.door43.org/unfoldingWord/en_tn/raw/branch/master';
const DEFAULT_OUT = path.join(__dirname, '..', 'data', 'bible_backgrounds.json');

const BOOKS = [
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
  '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
  'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
  'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL',
  'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH',
  'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
  '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchText(url, attempts = 3) {
  for (let i = 1; i <= attempts; i++) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
      return await res.text();
    } catch (e) {
      if (i === attempts) throw e;
      await sleep(1000 * i);
    }
  }
}

/**
 * Strips raw markdown links like [verse 1](../01/01.md) or [Exodus 24:3](../../exo/24/03.md)
 * into human-readable text like 'verse 1' or 'Exodus 24:3'.
 */
function cleanMarkdownLinks(text) {
  return text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');
}

/**
 * Removes pure translator mechanics while preserving cultural & historical facts.
 */
function cleanNoteContent(rawNote) {
  let note = rawNote.replace(/\\n/g, '\n');

  // Strip generic translator directives
  const sentences = note.split(/(?<=[.?!])\s+/);
  const filteredSentences = sentences.filter((s) => {
    const lower = s.toLowerCase();
    if (lower.includes('make sure that your translation')) return false;
    if (lower.includes('make sure you translate this')) return false;
    if (lower.includes('do what is natural in your language')) return false;
    if (lower.includes('consider whether or not it is best in your language')) return false;
    if (lower.includes('consider whether your language has')) return false;
    if (lower.includes('consider what is the best way to translate')) return false;
    if (lower.includes('be consistent here with how you translated')) return false;
    if (lower.includes('see how you translated this phrase in')) return false;
    if (lower.includes('see how you translated')) return false;
    if (lower.includes('in your translation, you could')) return false;
    if (lower.includes('in your language, it would appear')) return false;
    if (lower.includes('use a natural form in your language')) return false;
    if (lower.includes('use forms in your language that')) return false;
    if (lower.includes('use a form that indicates')) return false;
    if (lower.includes('you could reword this')) return false;
    if (lower.includes('each language has its own system of')) return false;
    if (lower.includes('decide what to do in your translation')) return false;
    if (lower.includes('every translation team needs to decide')) return false;
    return true;
  });

  note = filteredSentences.join(' ');
  note = cleanMarkdownLinks(note).trim();

  // Clean trailing "Alternate translation:" lines if they don't add historical context
  note = note.replace(/\s*Alternate translation:\s*\[[^\]]+\]/gi, '').trim();

  return note;
}

/**
 * Determines whether a note has historical, cultural, custom, geographical, or ancient idiom context.
 */
function isHistoricalOrCultural(ref, supportRef, note, quote) {
  const text = (note + ' ' + (supportRef || '') + ' ' + (quote || '')).toLowerCase();

  // Chapter introductions always contain rich historical/narrative background
  if (ref.endsWith(':intro') || ref.includes('front:intro')) {
    return true;
  }

  // Strong signals from unfoldingWord translationAcademy categories
  if (supportRef) {
    if (
      supportRef.includes('figs-custom') ||
      supportRef.includes('figs-idiom') ||
      supportRef.includes('translate-names') ||
      supportRef.includes('translate-unknown') ||
      supportRef.includes('figs-metaphor') ||
      supportRef.includes('figs-personification')
    ) {
      return true;
    }
  }

  // Cultural and historical keywords
  const keywords = [
    'custom', 'culture', 'cultural', 'ancient', 'tradition', 'history',
    'historical', 'geograph', 'archaeolog', 'hebrew', 'greek', 'roman',
    'jewish', 'egypt', 'babylon', 'persia', 'covenant', 'ritual',
    'sacrifice', 'temple', 'synagogue', 'law', 'measure', 'weight',
    'shekel', 'talent', 'coin', 'drachma', 'denarius', 'garment',
    'clothing', 'mourn', 'feast', 'passover', 'sabbath', 'leaven',
    'centurion', 'governor', 'caesar', 'pharaoh', 'king', 'priest',
    'levite', 'samaritan', 'pharisee', 'sadducee', 'rabbi', 'parable',
    'symbol', 'idiom', 'expression', 'cosmology', 'creation', 'flood'
  ];

  return keywords.some((kw) => text.includes(kw));
}

function deriveTopic(quote, note, ref) {
  if (ref.endsWith(':intro')) return 'Chapter Overview';

  // Extract bolded keyword or phrase if present in note
  const boldMatch = note.match(/\*\*([^*]+)\*\*/);
  if (boldMatch && boldMatch[1].length < 45) {
    return boldMatch[1].trim();
  }

  // Extract quoted English word
  const quoteMatch = note.match(/[“"]([^”"]+)[”"]/);
  if (quoteMatch && quoteMatch[1].length > 2 && quoteMatch[1].length < 40) {
    return quoteMatch[1].trim();
  }

  // Clean quote of zero-width joiners and non-Latin characters
  let cleanQuote = (quote || '').replace(/[\u200B-\u200D\uFEFF]/g, '').trim();
  if (/[a-zA-Z]/.test(cleanQuote) && cleanQuote.length < 40) {
    return cleanQuote;
  }

  // Fallback to first clause of note
  const firstClause = note.split(/[:;,.\n]/)[0].replace(/[\u200B-\u200D\uFEFF]/g, '').trim();
  if (firstClause.length > 3 && firstClause.length < 45) {
    return firstClause;
  }

  return 'Historical & Cultural Context';
}

async function main() {
  const args = process.argv.slice(2);
  const isSample = args.includes('--sample');
  const targetBooks = isSample ? ['GEN', 'MAT'] : BOOKS;
  const outPath = args.find((a) => !a.startsWith('--')) || DEFAULT_OUT;

  console.log(`Starting cultural backgrounds build...`);
  console.log(`Mode: ${isSample ? 'SAMPLE (GEN, MAT)' : 'FULL (66 Books)'}`);
  console.log(`Output: ${outPath}`);

  const backgrounds = {};
  let totalNotes = 0;
  let totalVerses = 0;

  for (const book of targetBooks) {
    const url = `${BASE_URL}/tn_${book}.tsv`;
    process.stdout.write(`Fetching ${book}... `);

    try {
      const tsvContent = await fetchText(url);
      const lines = tsvContent.split('\n');
      if (lines.length < 2) {
        console.log('empty file, skipping.');
        continue;
      }

      const header = lines[0].split('\t');
      const refIdx = header.indexOf('Reference');
      const idIdx = header.indexOf('ID');
      const supportRefIdx = header.indexOf('SupportReference');
      const quoteIdx = header.indexOf('Quote');
      const noteIdx = header.indexOf('Note');

      if (refIdx === -1 || noteIdx === -1) {
        console.log('invalid TSV header, skipping.');
        continue;
      }

      const bookMap = {};
      let bookNotesCount = 0;

      for (let i = 1; i < lines.length; i++) {
        const row = lines[i].split('\t');
        if (row.length <= Math.max(refIdx, noteIdx)) continue;

        const ref = row[refIdx] ? row[refIdx].trim() : '';
        const noteRaw = row[noteIdx] ? row[noteIdx].trim() : '';
        const supportRef = supportRefIdx !== -1 ? row[supportRefIdx]?.trim() : '';
        const quote = quoteIdx !== -1 ? row[quoteIdx]?.trim() : '';
        const id = idIdx !== -1 ? row[idIdx]?.trim() : `n_${i}`;

        if (!ref || !noteRaw || ref === 'front:intro') continue;

        // Determine chapter and verse
        let chapter = 1;
        let verse = 0; // 0 = chapter intro

        if (ref.endsWith(':intro')) {
          chapter = parseInt(ref.split(':')[0], 10);
          verse = 0;
        } else if (ref.includes(':')) {
          const parts = ref.split(':');
          chapter = parseInt(parts[0], 10);
          verse = parseInt(parts[1], 10);
        } else {
          continue;
        }

        if (isNaN(chapter) || isNaN(verse)) continue;

        // Check if note contains cultural/historical context
        if (!isHistoricalOrCultural(ref, supportRef, noteRaw, quote)) {
          continue;
        }

        const cleanedNote = cleanNoteContent(noteRaw);
        if (!cleanedNote || cleanedNote.length < 15) continue;

        const topic = deriveTopic(quote, cleanedNote, ref);

        const chKey = String(chapter);
        if (!bookMap[chKey]) {
          bookMap[chKey] = [];
        }

        let verseEntry = bookMap[chKey].find((e) => e.v === verse);
        if (!verseEntry) {
          verseEntry = { v: verse, notes: [] };
          bookMap[chKey].push(verseEntry);
          totalVerses++;
        }

        verseEntry.notes.push({
          id,
          topic,
          quote: quote ? cleanMarkdownLinks(quote) : undefined,
          text: cleanedNote,
        });

        bookNotesCount++;
        totalNotes++;
      }

      backgrounds[book] = bookMap;
      console.log(`OK (${bookNotesCount} notes)`);
      await sleep(200); // Be respectful to Door43
    } catch (err) {
      console.error(`Failed for ${book}:`, err.message);
    }
  }

  const canonical = JSON.stringify(backgrounds);
  const sha256 = crypto.createHash('sha256').update(canonical, 'utf8').digest('hex');

  const payload = {
    sha256,
    version: '1.0.0',
    source: 'unfoldingWord Translation Notes (CC BY-SA 4.0)',
    backgrounds,
  };

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(payload));

  const sizeKb = (fs.statSync(outPath).size / 1024).toFixed(1);
  console.log(`\nBuild complete!`);
  console.log(`  Books processed: ${Object.keys(backgrounds).length}`);
  console.log(`  Verses with context: ${totalVerses}`);
  console.log(`  Total cultural notes: ${totalNotes}`);
  console.log(`  SHA-256: ${sha256}`);
  console.log(`  Output file: ${outPath} (${sizeKb} KB)`);
}

main().catch((err) => {
  console.error('Fatal error in build_cultural_backgrounds:', err);
  process.exit(1);
});
