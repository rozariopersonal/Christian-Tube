export interface ScriptureCitation {
  book?: string; // 3-letter Bible book code e.g. MAT, ROM, GEN
  chapter?: number;
  verse?: number;
}

export interface VideoChapter {
  title: string;
  seconds: number;
  timestamp: string;
}

export interface ExtractedVideoMetadata {
  speaker?: string;
  language?: string;
  secondaryLanguage?: string;
  cleanTitle?: string;
  subSeries?: string;
  partNumber?: number;
  meetingType?: string;
  location?: string;
  targetAudience?: string;
  topics?: string[];
  scripture?: ScriptureCitation;
  chapters?: VideoChapter[];
}

export interface MetadataExtractorInput {
  title: string;
  description?: string;
  channelTitle?: string;
  tags?: string[];
}

// 50+ Known CFC Elders & Speakers (standardized canonical names)
const KNOWN_SPEAKERS: string[] = [
  'Zac Poonen',
  'Ian Poonen',
  'Santosh Poonen',
  'Sandeep Poonen',
  'Bobby Babu',
  'George Mathew',
  'Suresh Babu',
  'Thomas Abraham',
  'Biju Chacko',
  'Sunny Varghese',
  'K.O. John',
  'Vinod Babu',
  'John Thomas',
  'Zac Cherian',
  'S. Johnson',
  'Vivek',
  'Philip Eapen',
  'Anand Dawson',
  'Eric',
  'David',
  'Joshua',
  'Sam Abraham',
  'Vimal',
  'Prabhudas',
  'Finny',
  'Enoch',
  'Benny',
  'Shibu',
  'Elias',
  'Jagan',
  'Sasi',
  'G.V.',
  'Clement',
  'Stephen',
  'Daniel',
  'Prathap',
  'Rajesh',
  'Saju',
  'Sunil',
  'Paul',
  'Prem',
  'Naveen',
  'Robin',
  'Solomon',
  'Wilson',
  'Mathew',
  'Philip',
  'Jacob',
  'Benjamin',
  'Joseph',
];

// Common Bible Book Alias -> Standard 3-Letter Code
const BIBLE_BOOKS_MAP: Record<string, string> = {
  genesis: 'GEN', gen: 'GEN', ge: 'GEN',
  exodus: 'EXO', exo: 'EXO', ex: 'EXO',
  leviticus: 'LEV', lev: 'LEV', le: 'LEV',
  numbers: 'NUM', num: 'NUM', nu: 'NUM',
  deuteronomy: 'DEU', deut: 'DEU', dt: 'DEU',
  joshua: 'JOS', josh: 'JOS',
  judges: 'JDG', judg: 'JDG', jdg: 'JDG',
  ruth: 'RUT', rut: 'RUT', rth: 'RUT',
  '1 samuel': '1SA', '1samuel': '1SA', '1 sam': '1SA', '1sam': '1SA', '1sa': '1SA',
  '2 samuel': '2SA', '2samuel': '2SA', '2 sam': '2SA', '2sam': '2SA', '2sa': '2SA',
  '1 kings': '1KI', '1kings': '1KI', '1 ki': '1KI', '1kgs': '1KI', '1ki': '1KI',
  '2 kings': '2KI', '2kings': '2KI', '2 ki': '2KI', '2kgs': '2KI', '2ki': '2KI',
  '1 chronicles': '1CH', '1chronicles': '1CH', '1 chr': '1CH', '1chr': '1CH', '1ch': '1CH',
  '2 chronicles': '2CH', '2chronicles': '2CH', '2 chr': '2CH', '2chr': '2CH', '2ch': '2CH',
  ezra: 'EZR', ezr: 'EZR',
  nehemiah: 'NEH', neh: 'NEH', ne: 'NEH',
  esther: 'EST', est: 'EST', esth: 'EST',
  job: 'JOB', jb: 'JOB',
  psalms: 'PSA', psalm: 'PSA', psa: 'PSA', ps: 'PSA',
  proverbs: 'PRO', prov: 'PRO', pro: 'PRO', pr: 'PRO',
  ecclesiastes: 'ECC', eccl: 'ECC', ecc: 'ECC', ec: 'ECC',
  'song of solomon': 'SNG', 'song of songs': 'SNG', canticles: 'SNG', song: 'SNG', sng: 'SNG',
  isaiah: 'ISA', isa: 'ISA', is: 'ISA',
  jeremiah: 'JER', jer: 'JER', je: 'JER',
  lamentations: 'LAM', lam: 'LAM', la: 'LAM',
  ezekiel: 'EZK', ezek: 'EZK', ezk: 'EZK',
  daniel: 'DAN', dan: 'DAN', da: 'DAN',
  hosea: 'HOS', hos: 'HOS', ho: 'HOS',
  joel: 'JOL', jol: 'JOL', joe: 'JOL',
  amos: 'AMO', amos_: 'AMO', am: 'AMO', amo: 'AMO',
  obadiah: 'OBA', obad: 'OBA', oba: 'OBA',
  jonah: 'JON', jon: 'JON', jnh: 'JON',
  micah: 'MIC', mic: 'MIC', mc: 'MIC',
  nahum: 'NAM', nah: 'NAM', nam: 'NAM',
  habakkuk: 'HAB', hab: 'HAB',
  zephaniah: 'ZEP', zeph: 'ZEP', zep: 'ZEP',
  haggai: 'HAG', hag: 'HAG',
  zechariah: 'ZEC', zech: 'ZEC', zec: 'ZEC',
  malachi: 'MAL', mal: 'MAL',
  matthew: 'MAT', matt: 'MAT', mat: 'MAT', mt: 'MAT',
  mark: 'MRK', mrk: 'MRK', mk: 'MRK',
  luke: 'LUK', luk: 'LUK', lk: 'LUK',
  john: 'JHN', jhn: 'JHN', jn: 'JHN',
  acts: 'ACT', act: 'ACT', ac: 'ACT',
  romans: 'ROM', rom: 'ROM', ro: 'ROM', rm: 'ROM',
  '1 corinthians': '1CO', '1corinthians': '1CO', '1 cor': '1CO', '1cor': '1CO', '1co': '1CO',
  '2 corinthians': '2CO', '2corinthians': '2CO', '2 cor': '2CO', '2cor': '2CO', '2co': '2CO',
  galatians: 'GAL', gal: 'GAL', ga: 'GAL',
  ephesians: 'EPH', eph: 'EPH', ep: 'EPH',
  philippians: 'PHP', phil: 'PHP', php: 'PHP',
  colossians: 'COL', col: 'COL',
  '1 thessalonians': '1TH', '1thessalonians': '1TH', '1 thess': '1TH', '1th': '1TH',
  '2 thessalonians': '2TH', '2thessalonians': '2TH', '2 thess': '2TH', '2th': '2TH',
  '1 timothy': '1TI', '1timothy': '1TI', '1 tim': '1TI', '1ti': '1TI',
  '2 timothy': '2TI', '2timothy': '2TI', '2 tim': '2TI', '2ti': '2TI',
  titus: 'TIT', tit: 'TIT',
  philemon: 'PHM', phm: 'PHM',
  hebrews: 'HEB', heb: 'HEB',
  james: 'JAS', jas: 'JAS', jam: 'JAS', jm: 'JAS',
  '1 peter': '1PE', '1peter': '1PE', '1 pet': '1PE', '1pe': '1PE', '1pt': '1PE',
  '2 peter': '2PE', '2peter': '2PE', '2 pet': '2PE', '2pe': '2PE', '2pt': '2PE',
  '1 john': '1JN', '1john': '1JN', '1 jn': '1JN', '1jn': '1JN',
  '2 john': '2JN', '2john': '2JN', '2 jn': '2JN', '2jn': '2JN',
  '3 john': '3JN', '3john': '3JN', '3 jn': '3JN', '3jn': '3JN',
  jude: 'JUD', jud: 'JUD', jd: 'JUD',
  revelation: 'REV', rev: 'REV', revelations: 'REV', re: 'REV',
};

// Known Sub-Series List
const KNOWN_SERIES = [
  'Through The Bible',
  'All That Jesus Taught',
  'Sermon on the Mount',
  'The New Covenant',
  'Basic Christian Truths',
  'Secret of Godliness',
  'Living as Jesus Lived',
  'A Heavenly Way of Life',
  'Church Truths',
  'Spiritual Leadership',
  'Full Gospel',
  'Building the Body of Christ',
  'Discipleship',
  'Romans Study',
  'Hebrews Study',
  'Revelation Study',
  'The Beatitudes',
  'The Tabernacle',
  'Christian Fellowship Church',
];

// Meeting Types Regex Map
const MEETING_TYPES: Array<{ type: string; pattern: RegExp }> = [
  { type: 'Sunday Service', pattern: /\b(sunday\s*(service|morning|meeting)?|lord'?s\s*day)\b/i },
  { type: 'Midweek Meeting', pattern: /\b(mid[- ]?week|wednesday|tuesday|thursday|bible\s*study)\b/i },
  { type: 'Youth Camp', pattern: /\b(youth\s*(camp|conference|meeting|retreat)?|teens|young\s*people)\b/i },
  { type: 'Annual Conference', pattern: /\b(annual\s*conference|conference\s*\d{4}|conference)\b/i },
  { type: 'Workers Conference', pattern: /\b(workers?\s*conference|elders?\s*meeting|leaders?\s*meeting)\b/i },
  { type: 'Brothers Meeting', pattern: /\b(brothers?\s*meeting|men'?s\s*meeting)\b/i },
  { type: 'Sisters Meeting', pattern: /\b(sisters?\s*meeting|women'?s\s*meeting)\b/i },
  { type: 'Prayer Meeting', pattern: /\b(prayer\s*meeting|all\s*night\s*prayer|fasting\s*prayer)\b/i },
  { type: 'Communion', pattern: /\b(communion|lord'?s\s*table|breaking\s*of\s*bread)\b/i },
  { type: 'Wedding Service', pattern: /\b(wedding|marriage\s*service)\b/i },
  { type: 'Memorial / Funeral', pattern: /\b(memorial|funeral)\b/i },
  { type: 'Family Camp', pattern: /\b(family\s*(camp|conference|retreat)|couples\s*retreat)\b/i },
];

// Locations Regex Map
const LOCATIONS = [
  'Chennai',
  'Bangalore',
  'Coimbatore',
  'Loveland',
  'London',
  'Dubai',
  'Singapore',
  'Mumbai',
  'Delhi',
  'Hyderabad',
  'Pune',
  'Kottayam',
  'Trivandrum',
  'Kochi',
  'Salem',
  'Madurai',
  'Trichy',
  'Vellore',
  'Tirunelveli',
  'Sydney',
  'Chicago',
  'San Jose',
  'Dallas',
  'Houston',
  'Toronto',
];

// Target Audiences
const TARGET_AUDIENCES: Array<{ audience: string; pattern: RegExp }> = [
  { audience: 'Youth', pattern: /\b(youth|young\s*people|teens|teenagers|campus)\b/i },
  { audience: 'Married Couples / Families', pattern: /\b(couples|marriage|husband|wife|parents|parenting|family)\b/i },
  { audience: 'Elders / Leaders', pattern: /\b(elders?|leaders?|workers?|servants?|ministers?)\b/i },
  { audience: 'Sisters', pattern: /\b(sisters?|women|mothers?)\b/i },
  { audience: 'Brothers', pattern: /\b(brothers?|men|fathers?)\b/i },
  { audience: 'Children', pattern: /\b(children|sunday\s*school|kids)\b/i },
];

// Topic Classification Rules
const TOPIC_KEYWORDS: Array<{ topic: string; pattern: RegExp }> = [
  { topic: 'Holiness', pattern: /\b(holiness|holy|pure|purity|victory over sin|overcoming sin|temptation|sinless)\b/i },
  { topic: 'The Cross', pattern: /\b(the cross|crucified|deny self|self denial|dying to self|take up cross)\b/i },
  { topic: 'Holy Spirit', pattern: /\b(holy spirit|baptism in the spirit|fullness of the spirit|spiritual gifts|tongues)\b/i },
  { topic: 'Discipleship', pattern: /\b(disciple|discipleship|follow jesus|obedience|obey|surrender)\b/i },
  { topic: 'New Covenant', pattern: /\b(new covenant|law and grace|old covenant|body of christ|covenant life)\b/i },
  { topic: 'Humility', pattern: /\b(humility|humble|pride|proud|brokenness|contrite)\b/i },
  { topic: 'Prayer & Fasting', pattern: /\b(prayer|praying|intercession|fasting|supplication)\b/i },
  { topic: 'Faith', pattern: /\b(faith|trusting god|belief|unbelief|doubt)\b/i },
  { topic: 'Love & Forgiveness', pattern: /\b(love|forgive|forgiveness|bitterness|grudge|reconciliation|unity)\b/i },
  { topic: 'Family & Marriage', pattern: /\b(marriage|husband|wife|parenting|children|family|home)\b/i },
  { topic: 'Spiritual Warfare', pattern: /\b(spiritual warfare|satan|devil|demons?|armor of god|resist the devil)\b/i },
  { topic: 'Church & Fellowship', pattern: /\b(church|fellowship|body of christ|assembly|eldership|local church)\b/i },
  { topic: 'Finances & Money', pattern: /\b(money|mammon|finances|financial|giving|tithe|greed|wealth)\b/i },
  { topic: 'Suffering & Trials', pattern: /\b(suffering|trials?|tribulation|persecution|affliction|hardship)\b/i },
  { topic: 'End Times & Prophecy', pattern: /\b(end times|second coming|antichrist|prophecy|rapture|revelation)\b/i },
  { topic: 'Grace', pattern: /\b(grace|mercy|justification|righteousness of god|condemnation)\b/i },
  { topic: 'Evangelism & Witness', pattern: /\b(evangelism|gospel|witnessing|soul winning|testimony)\b/i },
  { topic: 'Praise & Worship', pattern: /\b(praise|worship|thanksgiving|glorify god)\b/i },
];

export function romanToDecimal(roman: string): number {
  const map: Record<string, number> = {
    I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000,
  };
  const str = roman.toUpperCase();
  let result = 0;
  for (let i = 0; i < str.length; i++) {
    const current = map[str[i]] || 0;
    const next = map[str[i + 1]] || 0;
    if (current < next) {
      result -= current;
    } else {
      result += current;
    }
  }
  return result > 0 ? result : 0;
}

/**
 * Extracts comprehensive semantic metadata from a YouTube video
 */
export function extractVideoMetadata(input: MetadataExtractorInput): ExtractedVideoMetadata {
  const { title = '', description = '', channelTitle = '', tags = [] } = input;
  const combinedText = `${title}\n${description}\n${channelTitle}\n${tags.join(' ')}`;

  // 1. Speaker Extraction
  let speaker: string | undefined;

  // Check explicit known speakers
  for (const name of KNOWN_SPEAKERS) {
    const regex = new RegExp(`\\b(?:Bro(?:ther)?\\.?\\s*)?${name.replace('.', '\\.')}\\b`, 'i');
    if (regex.test(title)) {
      speaker = name;
      break;
    }
  }

  // Fallback regex patterns on Title & Description
  if (!speaker) {
    const patterns = [
      /\b(?:Bro(?:ther)?\.?\s+)([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/,
      /\b(?:Speaker|By|by):\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/,
      /[-|–]\s*(?:Bro(?:ther)?\.?\s*)?([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s*$/,
    ];
    for (const pat of patterns) {
      const match = title.match(pat);
      if (match && match[1]) {
        const candidate = match[1].trim();
        // Ignore noise words
        if (!['Sunday', 'Midweek', 'Youth', 'CFC', 'Service', 'English', 'Tamil', 'Part'].includes(candidate)) {
          speaker = candidate;
          break;
        }
      }
    }
  }

  // 2. Language & Secondary Language Detection
  let language: string = 'English';
  let secondaryLanguage: string | undefined;

  const hasTamil = /[\u0B80-\u0BFF]/.test(combinedText) || /\b(tamil|தமிழ்)\b/i.test(combinedText);
  const hasTelugu = /[\u0C00-\u0C7F]/.test(combinedText) || /\b(telugu|తెలుగు)\b/i.test(combinedText);
  const hasMalayalam = /[\u0D00-\u0D7F]/.test(combinedText) || /\b(malayalam|മലയാളം)\b/i.test(combinedText);
  const hasHindi = /[\u0900-\u097F]/.test(combinedText) || /\b(hindi|हिन्दी)\b/i.test(combinedText);
  const hasKannada = /[\u0C80-\u0CFF]/.test(combinedText) || /\b(kannada|ಕನ್ನಡ)\b/i.test(combinedText);

  // Check bilingual markers
  const bilingualMatch = title.match(/\[([A-Za-z]+)\s*[-&/]\s*([A-Za-z]+)\]/i) ||
                         title.match(/\(([A-Za-z]+)\s*[-&/]\s*([A-Za-z]+)\)/i);

  if (bilingualMatch) {
    language = bilingualMatch[1].trim();
    secondaryLanguage = bilingualMatch[2].trim();
  } else if (hasTamil) {
    language = 'Tamil';
    if (/[a-zA-Z]{4,}/.test(title)) {
      secondaryLanguage = 'English';
    }
  } else if (hasTelugu) {
    language = 'Telugu';
    if (/[a-zA-Z]{4,}/.test(title)) {
      secondaryLanguage = 'English';
    }
  } else if (hasMalayalam) {
    language = 'Malayalam';
    if (/[a-zA-Z]{4,}/.test(title)) {
      secondaryLanguage = 'English';
    }
  } else if (hasHindi) {
    language = 'Hindi';
    if (/[a-zA-Z]{4,}/.test(title)) {
      secondaryLanguage = 'English';
    }
  } else if (hasKannada) {
    language = 'Kannada';
    if (/[a-zA-Z]{4,}/.test(title)) {
      secondaryLanguage = 'English';
    }
  } else if (channelTitle.toLowerCase().includes('tamil') || channelTitle.toLowerCase().includes('chennai') || channelTitle.toLowerCase().includes('coimbatore')) {
    language = 'Tamil';
    secondaryLanguage = 'English';
  } else {
    language = 'English';
  }

  // 3. SubSeries and Part Number
  let subSeries: string | undefined;
  let partNumber: number | undefined;

  for (const s of KNOWN_SERIES) {
    if (new RegExp(`\\b${s}\\b`, 'i').test(title) || new RegExp(`\\b${s}\\b`, 'i').test(description.slice(0, 300))) {
      subSeries = s;
      break;
    }
  }

  // Part number extraction
  const partMatch = title.match(/\b(?:part|pt|episode|vol|lesson|#)\.?\s*([0-9]+|[ivxlcdm]+)\b/i) ||
                    title.match(/\b([0-9]+)\s*(?:of|\/)\s*([0-9]+)\b/i);

  if (partMatch) {
    const rawVal = partMatch[1];
    if (/^\d+$/.test(rawVal)) {
      partNumber = parseInt(rawVal, 10);
    } else if (/^[ivxlcdm]+$/i.test(rawVal)) {
      partNumber = romanToDecimal(rawVal);
    }
  }

  // 4. Meeting Type
  let meetingType: string | undefined;
  for (const mt of MEETING_TYPES) {
    if (mt.pattern.test(title) || mt.pattern.test(description.slice(0, 300))) {
      meetingType = mt.type;
      break;
    }
  }
  if (!meetingType) {
    meetingType = 'General Sermons';
  }

  // 5. Location
  let location: string | undefined;
  for (const loc of LOCATIONS) {
    const locRegex = new RegExp(`\\b${loc}\\b`, 'i');
    if (locRegex.test(title) || locRegex.test(channelTitle) || locRegex.test(description.slice(0, 300))) {
      location = loc;
      break;
    }
  }

  // 6. Target Audience
  let targetAudience: string = 'General';
  for (const ta of TARGET_AUDIENCES) {
    if (ta.pattern.test(title) || ta.pattern.test(description.slice(0, 300))) {
      targetAudience = ta.audience;
      break;
    }
  }

  // 7. Topics (Multi-label classification)
  const topics: string[] = [];
  for (const t of TOPIC_KEYWORDS) {
    if (t.pattern.test(title) || t.pattern.test(description.slice(0, 500))) {
      topics.push(t.topic);
      if (topics.length >= 4) break;
    }
  }

  // 8. Scripture Citation Extraction
  let scripture: ScriptureCitation | undefined;
  // Match e.g. "Romans 8:28", "Rom 8:28", "1 Cor 13", "MAT 5:3-12", "Matthew 5:3"
  const globalScriptureRegex = /\b((?:[1-3]\s*)?[A-Za-z]+)\s*(\d{1,3})(?::(\d{1,3}))?\b/g;
  const searchTexts = [title, description.slice(0, 500)];

  for (const text of searchTexts) {
    if (!text) continue;
    let match: RegExpExecArray | null;
    while ((match = globalScriptureRegex.exec(text)) !== null) {
      const rawBook = match[1].toLowerCase().replace(/\s+/g, ' ').trim();
      const bookCode = BIBLE_BOOKS_MAP[rawBook];
      if (bookCode) {
        scripture = {
          book: bookCode,
          chapter: parseInt(match[2], 10),
          verse: match[3] ? parseInt(match[3], 10) : undefined,
        };
        break;
      }
    }
    if (scripture) break;
  }

  // 9. Chapter Timestamps Extraction from Description
  const chapters: VideoChapter[] = [];
  if (description) {
    const lines = description.split(/\r?\n/);
    const timeRegex = /(?:(\d{1,2}):)?(\d{2}):(\d{2})/;

    for (const line of lines) {
      const match = line.match(timeRegex);
      if (match) {
        const fullTimestamp = match[0];
        const hours = match[1] ? parseInt(match[1], 10) : 0;
        const minutes = parseInt(match[2], 10);
        const seconds = parseInt(match[3], 10);
        const totalSeconds = hours * 3600 + minutes * 60 + seconds;

        // Clean chapter title line
        const chTitle = line
          .replace(fullTimestamp, '')
          .replace(/^[-–—:| ]+/, '')
          .replace(/[-–—:| ]+$/, '')
          .trim();

        if (chTitle.length > 2) {
          chapters.push({
            title: chTitle,
            seconds: totalSeconds,
            timestamp: fullTimestamp,
          });
        }
      }
    }
  }

  // 10. Clean Title Generation
  let cleanTitle = title
    .replace(/\[.*?\]/g, '') // Remove [Tamil-English], [HD], etc.
    .replace(/\(.*?\)/g, (match) => {
      // Keep parentheses if it's a scripture or part number, otherwise strip
      if (/\b(?:Part|Pt|\d+|ROM|MAT|GEN)\b/i.test(match)) return match;
      return '';
    })
    .replace(/#\S+/g, '') // Remove #Shorts, #CFC
    .replace(/\|\s*CFC\s*[^|]*/gi, '') // Remove channel suffix
    .replace(/\|\s*Christian Fellowship Church[^|]*/gi, '')
    .replace(/\|\s*Bro\.?\s*[^|]*/gi, '') // Remove speaker pipe
    .replace(/[-|–•]\s*Bro\.?\s*.*$/i, '')
    .replace(/[-|–•]\s*Zac Poonen.*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();

  // Strip dangling punctuation
  cleanTitle = cleanTitle.replace(/^[-–—:|/• ]+|[-–—:|/• ]+$/g, '').trim();
  if (!cleanTitle) cleanTitle = title;

  return {
    speaker,
    language,
    secondaryLanguage,
    cleanTitle,
    subSeries,
    partNumber,
    meetingType,
    location,
    targetAudience,
    topics: topics.length > 0 ? topics : undefined,
    scripture,
    chapters: chapters.length > 0 ? chapters : undefined,
  };
}
