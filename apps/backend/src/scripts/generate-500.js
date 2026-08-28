const fs = require('fs');
const path = require('path');

const csvPath = 'd:\\Projects\\Christian-Tube\\test.csv';
const outPath = 'd:\\Projects\\Christian-Tube\\apps\\backend\\src\\modules\\words\\data\\scriptures.data.ts';

const PROPHETS_AND_NT = [
  'ISA', 'JER', 'LAM', 'EZE', 'DAN', 'HOS', 'JOE', 'AMO', 'OBA', 'JON', 'MIC', 'NAH', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL',
  'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH', 'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS', '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
  // alternate spellings sometimes used
  'MAR', 'JOH', 'JAM', '1 JO', '2 JO', '3 JO'
];

const BOOKS_MAP = {
  'ISA': { num: 23, name: 'Isaiah' },
  'JER': { num: 24, name: 'Jeremiah' },
  'LAM': { num: 25, name: 'Lamentations' },
  'EZE': { num: 26, name: 'Ezekiel' },
  'DAN': { num: 27, name: 'Daniel' },
  'HOS': { num: 28, name: 'Hosea' },
  'JOE': { num: 29, name: 'Joel' },
  'AMO': { num: 30, name: 'Amos' },
  'OBA': { num: 31, name: 'Obadiah' },
  'JON': { num: 32, name: 'Jonah' },
  'MIC': { num: 33, name: 'Micah' },
  'NAH': { num: 34, name: 'Nahum' },
  'HAB': { num: 35, name: 'Habakkuk' },
  'ZEP': { num: 36, name: 'Zephaniah' },
  'HAG': { num: 37, name: 'Haggai' },
  'ZEC': { num: 38, name: 'Zechariah' },
  'MAL': { num: 39, name: 'Malachi' },
  'MAT': { num: 40, name: 'Matthew' },
  'MRK': { num: 41, name: 'Mark' },
  'MAR': { num: 41, name: 'Mark' },
  'LUK': { num: 42, name: 'Luke' },
  'JHN': { num: 43, name: 'John' },
  'JOH': { num: 43, name: 'John' },
  'ACT': { num: 44, name: 'Acts' },
  'ROM': { num: 45, name: 'Romans' },
  '1CO': { num: 46, name: '1 Corinthians' },
  '2CO': { num: 47, name: '2 Corinthians' },
  'GAL': { num: 48, name: 'Galatians' },
  'EPH': { num: 49, name: 'Ephesians' },
  'PHP': { num: 50, name: 'Philippians' },
  'COL': { num: 51, name: 'Colossians' },
  '1TH': { num: 52, name: '1 Thessalonians' },
  '2TH': { num: 53, name: '2 Thessalonians' },
  '1TI': { num: 54, name: '1 Timothy' },
  '2TI': { num: 55, name: '2 Timothy' },
  'TIT': { num: 56, name: 'Titus' },
  'PHM': { num: 57, name: 'Philemon' },
  'HEB': { num: 58, name: 'Hebrews' },
  'JAS': { num: 59, name: 'James' },
  'JAM': { num: 59, name: 'James' },
  '1PE': { num: 60, name: '1 Peter' },
  '2PE': { num: 61, name: '2 Peter' },
  '1JN': { num: 62, name: '1 John' },
  '1 JO': { num: 62, name: '1 John' },
  '2JN': { num: 63, name: '2 John' },
  '2 JO': { num: 63, name: '2 John' },
  '3JN': { num: 64, name: '3 John' },
  '3 JO': { num: 64, name: '3 John' },
  'JUD': { num: 65, name: 'Jude' },
  'REV': { num: 66, name: 'Revelation' }
};

function parseReferences(text, category) {
  const verses = [];
  // basic regex to find Book CH:V or Book CH:V-V
  const regex = /([1-3]?\s?[A-Z]{2,3})\s+(\d+):(\d+)(?:-(\d+))?/g;
  let match;
  while ((match = regex.exec(text)) !== null) {
    let book = match[1].trim();
    if (PROPHETS_AND_NT.includes(book) && BOOKS_MAP[book]) {
      const bInfo = BOOKS_MAP[book];
      const chapter = parseInt(match[2], 10);
      const startVerse = parseInt(match[3], 10);
      const endVerse = match[4] ? parseInt(match[4], 10) : startVerse;
      
      const refLabel = `${bInfo.name} ${chapter}:${startVerse}${endVerse > startVerse ? '-' + endVerse : ''}`;
      
      verses.push({
        engine: 'scripture',
        bookNumber: bInfo.num,
        bookName: bInfo.name,
        chapter,
        startVerse,
        endVerse,
        referenceLabel: refLabel,
        verseMappings: {},
        category: category,
        tags: [category],
        backgroundPreset: category === 'Promise' ? 'ocean_calm' : 'mountain_dawn',
        isFeatured: false
      });
    }
  }
  return verses;
}

try {
  const content = fs.readFileSync(csvPath, 'utf8');
  
  let allVerses = [];
  const lines = content.split('\n');
  
  for (const line of lines) {
    if (line.includes('PROMISE') || line.includes('Promise')) {
      const extracted = parseReferences(line, 'Promise');
      allVerses = allVerses.concat(extracted);
    } else if (line.includes('COMMAND') || line.includes('Command')) {
      const extracted = parseReferences(line, 'Commandment');
      allVerses = allVerses.concat(extracted);
    }
  }

  // Deduplicate
  const uniqueVerses = [];
  const seen = new Set();
  
  for (const v of allVerses) {
    if (!seen.has(v.referenceLabel)) {
      seen.add(v.referenceLabel);
      uniqueVerses.push(v);
    }
    if (uniqueVerses.length >= 700) {
      break;
    }
  }

  if (uniqueVerses.length < 500) {
    console.log(`Only found ${uniqueVerses.length} unique verses. Extracting general verses from NT/Prophets to reach 500...`);
    for (const line of lines) {
      const extracted = parseReferences(line, 'Promise');
      for (const v of extracted) {
         if (!seen.has(v.referenceLabel)) {
           seen.add(v.referenceLabel);
           uniqueVerses.push(v);
         }
         if (uniqueVerses.length >= 600) break;
      }
      if (uniqueVerses.length >= 600) break;
    }
  }

  const finalVerses = uniqueVerses.slice(0, 500);

  const outLines = [];
  outLines.push(`// AUTO-GENERATED FILE`);
  outLines.push(`// Contains ${finalVerses.length} unique verses from Prophets and New Testament`);
  outLines.push(`export const ALL_SCRIPTURES: any[] = ${JSON.stringify(finalVerses, null, 2)};`);

  fs.writeFileSync(outPath, outLines.join('\n'));
  console.log(`Successfully wrote ${finalVerses.length} unique verses to ${outPath}`);

} catch (err) {
  console.error(err);
}
