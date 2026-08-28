import * as https from 'https';
import * as fs from 'fs';
import * as path from 'path';
import * as readline from 'readline';

const CSV_URL = 'https://raw.githubusercontent.com/openbibleinfo/Cross-References/master/topical_bible.csv';
const OUTPUT_PATH = path.join(__dirname, '..', 'modules', 'words', 'data', 'scriptures.data.ts');

const CATEGORY_MAP: Record<string, string> = {
  'love': 'Love',
  'peace': 'Peace',
  'anxiety': 'Anxiety',
  'faith': 'Faith',
  'hope': 'Hope',
  'healing': 'Healing',
  'forgiveness': 'Forgiveness',
  'strength': 'Strength',
  'joy': 'Joy',
  'fear': 'Fear',
};

// Book mappings for standard names and numbers
const BOOKS = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth',
  '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther',
  'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel',
  'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
  'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians',
  '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation'
];

interface ParsedRef {
  bookName: string;
  bookNumber: number;
  chapter: number;
  startVerse: number;
  endVerse: number;
}

function parseReference(ref: string): ParsedRef | null {
  // Example: "John 3:16" or "1 Corinthians 13:4-8"
  const match = ref.match(/^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$/);
  if (!match) return null;
  const bookName = match[1];
  const bookNumber = BOOKS.indexOf(bookName) + 1;
  if (bookNumber === 0) return null; // Unrecognized book

  return {
    bookName,
    bookNumber,
    chapter: parseInt(match[2], 10),
    startVerse: parseInt(match[3], 10),
    endVerse: match[4] ? parseInt(match[4], 10) : parseInt(match[3], 10)
  };
}

async function fetchAndProcess() {
  console.log('Downloading topical bible CSV...');
  
  const tempFile = path.join(__dirname, 'temp_topical.csv');
  
  await new Promise((resolve, reject) => {
    https.get(CSV_URL, (res) => {
      const fileStream = fs.createWriteStream(tempFile);
      res.pipe(fileStream);
      fileStream.on('finish', () => {
        fileStream.close();
        resolve(null);
      });
    }).on('error', reject);
  });

  console.log('Processing data...');
  
  const fileStream = fs.createReadStream(tempFile);
  const rl = readline.createInterface({ input: fileStream, crlfDelay: Infinity });

  const versesMap = new Map<string, {
    refLabel: string,
    parsed: ParsedRef,
    topics: Set<string>,
    votes: number
  }>();

  let isFirstLine = true;
  for await (const line of rl) {
    if (isFirstLine) {
      isFirstLine = false;
      continue;
    }

    // Format: "topic","reference","votes"
    const parts = line.match(/(?:^|,)("(?:[^"]|"")*"|[^,]*)/g);
    if (!parts || parts.length < 3) continue;

    const topic = parts[0].replace(/^,?"?|"?$/g, '').toLowerCase();
    const reference = parts[1].replace(/^,?"?|"?$/g, '');
    const votes = parseInt(parts[2].replace(/^,?"?|"?$/g, ''), 10);

    if (votes < 10) continue; // Filter out low quality tags

    const parsed = parseReference(reference);
    if (!parsed) continue;

    if (!versesMap.has(reference)) {
      versesMap.set(reference, {
        refLabel: reference,
        parsed,
        topics: new Set([topic]),
        votes
      });
    } else {
      const entry = versesMap.get(reference)!;
      entry.topics.add(topic);
      entry.votes += votes;
    }
  }

  // Convert to array and filter out obscure verses (must have significant votes)
  const allVerses = Array.from(versesMap.values())
    .filter(v => v.votes >= 20)
    .sort((a, b) => b.votes - a.votes)
    .slice(0, 4000); // Take top 4000 verses

  console.log(`Generated \${allVerses.length} unique verses.`);

  // Generate output TS file
  const outLines = [];
  outLines.push(`// AUTO-GENERATED FILE`);
  outLines.push(`// Contains \${allVerses.length} unique references from OpenBible Topical Dataset`);
  outLines.push(`// No text is stored. The client will resolve the text from the bible databases.`);
  outLines.push(`export const ALL_SCRIPTURES: any[] = [`);

  for (const verse of allVerses) {
    const tags = Array.from(verse.topics).slice(0, 5); // max 5 tags
    // Pick the best mapped category or general
    let category = 'General';
    for (const tag of tags) {
      if (CATEGORY_MAP[tag]) {
        category = CATEGORY_MAP[tag];
        break;
      }
    }
    
    // Auto-assign background
    let bg = 'mountain_dawn';
    if (category === 'Peace') bg = 'ocean_calm';
    if (category === 'Strength') bg = 'desert_dusk';
    if (category === 'Love') bg = 'forest_sun';
    
    outLines.push(`  {`);
    outLines.push(`    engine: 'scripture',`);
    outLines.push(`    bookNumber: ${verse.parsed.bookNumber},`);
    outLines.push(`    bookName: '${verse.parsed.bookName}',`);
    outLines.push(`    chapter: ${verse.parsed.chapter},`);
    outLines.push(`    startVerse: ${verse.parsed.startVerse},`);
    outLines.push(`    endVerse: ${verse.parsed.endVerse},`);
    outLines.push(`    referenceLabel: '${verse.refLabel.replace(/'/g, "\\'")}',`);
    outLines.push(`    verseMappings: {},`);
    outLines.push(`    category: '${category}',`);
    outLines.push(`    tags: ${JSON.stringify(tags)},`);
    outLines.push(`    backgroundPreset: '${bg}',`);
    outLines.push(`    isFeatured: ${verse.votes > 100},`);
    outLines.push(`  },`);
  }
  
  outLines.push(`];`);

  fs.writeFileSync(OUTPUT_PATH, outLines.join('\n'));
  fs.unlinkSync(tempFile);
  
  console.log(`Successfully wrote \${allVerses.length} verses to \${OUTPUT_PATH}!`);
}

fetchAndProcess().catch(console.error);
