const fs = require('fs');
const path = require('path');

const csvPath = path.join(__dirname, '..', '..', '..', '..', 'test.csv'); // Since we saved it as test.csv in the root previously
const outPath = path.join(__dirname, '..', '..', 'data', 'scriptures.json'); // Write to apps/backend/data/scriptures.json

const BOOKS_MAP = {
  'GEN': { num: 1, name: 'Genesis' },
  'EXO': { num: 2, name: 'Exodus' },
  'LEV': { num: 3, name: 'Leviticus' },
  'NUM': { num: 4, name: 'Numbers' },
  'DEU': { num: 5, name: 'Deuteronomy' },
  'JOS': { num: 6, name: 'Joshua' },
  'JDG': { num: 7, name: 'Judges' },
  'RUT': { num: 8, name: 'Ruth' },
  '1SA': { num: 9, name: '1 Samuel' },
  '2SA': { num: 10, name: '2 Samuel' },
  '1KI': { num: 11, name: '1 Kings' },
  '2KI': { num: 12, name: '2 Kings' },
  '1CH': { num: 13, name: '1 Chronicles' },
  '2CH': { num: 14, name: '2 Chronicles' },
  'EZR': { num: 15, name: 'Ezra' },
  'NEH': { num: 16, name: 'Nehemiah' },
  'EST': { num: 17, name: 'Esther' },
  'JOB': { num: 18, name: 'Job' },
  'PSA': { num: 19, name: 'Psalms' },
  'PRO': { num: 20, name: 'Proverbs' },
  'ECC': { num: 21, name: 'Ecclesiastes' },
  'SNG': { num: 22, name: 'Song of Solomon' },
  'SOL': { num: 22, name: 'Song of Solomon' },
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

const bgPresets = ['mountain_dawn', 'ocean_calm', 'desert_dusk', 'forest_sun', 'starry_night'];

function capitalizeFirstLetter(string) {
  return string.charAt(0).toUpperCase() + string.slice(1).toLowerCase();
}

function processAll() {
  const fileContent = fs.readFileSync(csvPath, 'utf8');
  const lines = fileContent.split('\n');

  // Map to hold merged data: referenceLabel -> verseObject
  const mergedData = new Map();

  let currentSubject = '';

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    
    // Attempt to extract subject if it exists (very rough parse for CSV)
    // Naves structure: section,subject,entry
    const parts = line.split(',');
    if (parts.length >= 3 && parts[1] && !parts[1].startsWith('-')) {
       // Only capture if it's not part of a multiline entry
       if (parts[1].trim() !== '') {
          currentSubject = parts[1].replace(/['"]/g, '').trim();
       }
    }

    if (!currentSubject) continue;

    const topicFormatted = capitalizeFirstLetter(currentSubject);

    // Parse references
    const regex = /([1-3]?\s?[A-Z]{2,3})\s+(\d+):(\d+)(?:-(\d+))?/g;
    let match;
    while ((match = regex.exec(line)) !== null) {
      let book = match[1].trim();
      if (BOOKS_MAP[book]) {
        const bInfo = BOOKS_MAP[book];
        const chapter = parseInt(match[2], 10);
        const startVerse = parseInt(match[3], 10);
        const endVerse = match[4] ? parseInt(match[4], 10) : startVerse;
        
        const refLabel = `${bInfo.name} ${chapter}:${startVerse}${endVerse > startVerse ? '-' + endVerse : ''}`;

        if (!mergedData.has(refLabel)) {
           mergedData.set(refLabel, {
             engine: 'scripture',
             bookNumber: bInfo.num,
             bookName: bInfo.name,
             chapter: chapter,
             startVerse: startVerse,
             endVerse: endVerse,
             referenceLabel: refLabel,
             verseMappings: {},
             category: topicFormatted,
             tags: new Set([topicFormatted]),
             backgroundPreset: bgPresets[Math.floor(Math.random() * bgPresets.length)],
             isFeatured: false
           });
        } else {
           const existing = mergedData.get(refLabel);
           existing.tags.add(topicFormatted);
        }
      }
    }
  }

  const finalArray = Array.from(mergedData.values()).map(item => ({
    ...item,
    tags: Array.from(item.tags)
  }));

  const dataDir = path.dirname(outPath);
  if (!fs.existsSync(dataDir)) {
     fs.mkdirSync(dataDir, { recursive: true });
  }

  fs.writeFileSync(outPath, JSON.stringify(finalArray, null, 2));
  console.log(`Successfully merged and wrote ${finalArray.length} unique verses into scriptures.json`);
}

processAll();
