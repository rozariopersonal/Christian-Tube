import { Injectable } from '@angular/core';

export interface ParsedScriptureRef {
  bookNumber: number;
  bookName: string;
  chapter: number;
  startVerse: number;
  endVerse?: number;
  rawMatch: string;
}

export interface ScriptureSpanToken {
  text: string;
  ref: ParsedScriptureRef | null;
}

const BOOK_NAMES: readonly string[] = [
  '',
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth',
  '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra',
  'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon',
  'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
  'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
  'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians', '2 Corinthians',
  'Galatians', 'Ephesians', 'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
  '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter',
  '1 John', '2 John', '3 John', 'Jude', 'Revelation',
];

const ABBREV_TO_BOOK: Record<string, number> = {
  gen: 1, genesis: 1, ge: 1, gn: 1,
  ex: 2, exod: 2, exodus: 2, exo: 2,
  lev: 3, leviticus: 3, le: 3, lv: 3,
  num: 4, numbers: 4, nu: 4, nm: 4,
  deut: 5, deuteronomy: 5, deu: 5, dt: 5,
  josh: 6, joshua: 6, jos: 6,
  judg: 7, judges: 7, jdg: 7,
  ruth: 8, rut: 8,
  '1 sam': 9, '1 samuel': 9, '1sam': 9, '1sa': 9, 'i sam': 9, 'i samuel': 9,
  '2 sam': 10, '2 samuel': 10, '2sam': 10, '2sa': 10, 'ii sam': 10, 'ii samuel': 10,
  '1 kings': 11, '1 kgs': 11, '1 ki': 11, '1kings': 11, '1ki': 11, '1kgs': 11, 'i kings': 11,
  '2 kings': 12, '2 kgs': 12, '2 ki': 12, '2kings': 12, '2ki': 12, '2kgs': 12, 'ii kings': 12,
  '1 chron': 13, '1 chronicles': 13, '1 chr': 13, '1ch': 13, '1chron': 13, 'i chron': 13,
  '2 chron': 14, '2 chronicles': 14, '2 chr': 14, '2ch': 14, '2chron': 14, 'ii chron': 14,
  ezra: 15, ezr: 15,
  neh: 16, nehemiah: 16,
  esth: 17, esther: 17, est: 17,
  job: 18,
  ps: 19, psalm: 19, psalms: 19, psa: 19, pss: 19,
  prov: 20, proverbs: 20, pro: 20, prv: 20,
  eccl: 21, ecclesiastes: 21, ecc: 21, eccles: 21,
  song: 22, 'song of solomon': 22, 'song of songs': 22, sng: 22, sos: 22,
  isa: 23, isaiah: 23,
  jer: 24, jeremiah: 24,
  lam: 25, lamentations: 25,
  ezek: 26, ezekiel: 26, ezk: 26,
  dan: 27, daniel: 27,
  hos: 28, hosea: 28,
  joel: 29, joe: 29,
  amos: 30, am: 30,
  obad: 31, obadiah: 31, oba: 31,
  jonah: 32, jon: 32,
  mic: 33, micah: 33,
  nah: 34, nahum: 34, nam: 34,
  hab: 35, habakkuk: 35,
  zeph: 36, zephaniah: 36, zep: 36,
  hag: 37, haggai: 37,
  zech: 38, zechariah: 38, zec: 38,
  mal: 39, malachi: 39,
  matt: 40, matthew: 40, mat: 40, mt: 40,
  mark: 41, mrk: 41, mk: 41,
  luke: 42, luk: 42, lk: 42,
  john: 43, jhn: 43, jn: 43,
  acts: 44, act: 44,
  rom: 45, romans: 45, ro: 45,
  '1 cor': 46, '1 corinthians': 46, '1cor': 46, '1co': 46, 'i cor': 46, 'i corinthians': 46,
  '2 cor': 47, '2 corinthians': 47, '2cor': 47, '2co': 47, 'ii cor': 47, 'ii corinthians': 47,
  gal: 48, galatians: 48,
  eph: 49, ephesians: 49,
  phil: 50, philippians: 50, php: 50,
  col: 51, colossians: 51,
  '1 thess': 52, '1 thessalonians': 52, '1th': 52, '1thess': 52, 'i thess': 52,
  '2 thess': 53, '2 thessalonians': 53, '2th': 53, '2thess': 53, 'ii thess': 53,
  '1 tim': 54, '1 timothy': 54, '1ti': 54, '1tim': 54, 'i tim': 54,
  '2 tim': 55, '2 timothy': 55, '2ti': 55, '2tim': 55, 'ii tim': 55,
  titus: 56, tit: 56,
  philem: 57, philemon: 57, phm: 57,
  heb: 58, hebrews: 58,
  jas: 59, james: 59, jam: 59,
  '1 pet': 60, '1 peter': 60, '1pe': 60, '1pet': 60, '1pt': 60, 'i pet': 60,
  '2 pet': 61, '2 peter': 61, '2pe': 61, '2pet': 61, '2pt': 61, 'ii pet': 61,
  '1 john': 62, '1 jn': 62, '1jn': 62, '1john': 62, 'i john': 62, 'i jn': 62,
  '2 john': 63, '2 jn': 63, '2jn': 63, '2john': 63, 'ii john': 63,
  '3 john': 64, '3 jn': 64, '3jn': 64, '3john': 64, 'iii john': 64,
  jude: 65, jud: 65,
  rev: 66, revelation: 66, revelations: 66,
};

const TAG_REGEX = /\[ref:(\d+)\.(\d+)\.(\d+)(?:-(\d+))?\|([^\]]+)\]/g;
const INLINE_REGEX =
  /(?:^|(?<=[\s("\u201C;\[]))((?:[123]|I{1,3})\.?\s*)?([A-Za-z]{2,20}(?:\s+of\s+[A-Za-z]{2,20})?)\.?\s+(\d+)(?:[:.]\s*(\d+)(?:[-–](\d+))?)?(?=\s|$|[.;,!?)\u201D"–—])/g;

@Injectable({ providedIn: 'root' })
export class ScriptureRefParserService {
  parse(text: string): ScriptureSpanToken[] {
    if (!text) return [];
    if (text.includes('[ref:')) {
      return this.parseTagged(text);
    }
    return this.parseInline(text);
  }

  private parseTagged(text: string): ScriptureSpanToken[] {
    const tokens: ScriptureSpanToken[] = [];
    let lastIndex = 0;
    TAG_REGEX.lastIndex = 0;

    let match: RegExpExecArray | null;
    while ((match = TAG_REGEX.exec(text)) !== null) {
      if (match.index > lastIndex) {
        tokens.push({ text: text.slice(lastIndex, match.index), ref: null });
      }
      const bookNumber = Number(match[1]);
      const chapter = Number(match[2]);
      const startVerse = Number(match[3]);
      const endVerse = match[4] ? Number(match[4]) : undefined;
      const label = match[5];
      tokens.push({
        text: label,
        ref: {
          bookNumber,
          bookName: BOOK_NAMES[bookNumber] || `Book ${bookNumber}`,
          chapter,
          startVerse,
          endVerse,
          rawMatch: label,
        },
      });
      lastIndex = match.index + match[0].length;
    }

    if (lastIndex < text.length) {
      tokens.push({ text: text.slice(lastIndex), ref: null });
    }
    return tokens.length > 0 ? tokens : [{ text, ref: null }];
  }

  private parseInline(text: string): ScriptureSpanToken[] {
    const tokens: ScriptureSpanToken[] = [];
    let lastIndex = 0;
    INLINE_REGEX.lastIndex = 0;

    let match: RegExpExecArray | null;
    while ((match = INLINE_REGEX.exec(text)) !== null) {
      const ordinalRaw = (match[1] ?? '').trim().replace(/\.$/, '').toLowerCase();
      const ordinal =
        ordinalRaw === 'i'
          ? '1'
          : ordinalRaw === 'ii'
            ? '2'
            : ordinalRaw === 'iii'
              ? '3'
              : ordinalRaw;
      const bookWord = match[2].trim().toLowerCase();
      const lookupKey = ordinal ? `${ordinal} ${bookWord}` : bookWord;
      const bookNumber = ABBREV_TO_BOOK[lookupKey];
      const chapter = Number(match[3]);
      const startVerse = match[4] ? Number(match[4]) : 1;
      const endVerse = match[5] ? Number(match[5]) : undefined;

      // Require verse number and valid Bible book to avoid false positives on prose
      if (!bookNumber || !match[4] || !Number.isFinite(chapter) || chapter < 1) {
        INLINE_REGEX.lastIndex = match.index + 1;
        continue;
      }

      if (match.index > lastIndex) {
        tokens.push({ text: text.slice(lastIndex, match.index), ref: null });
      }
      const rawMatch = match[0];
      tokens.push({
        text: rawMatch,
        ref: {
          bookNumber,
          bookName: BOOK_NAMES[bookNumber] || match[2],
          chapter,
          startVerse,
          endVerse,
          rawMatch,
        },
      });
      lastIndex = match.index + rawMatch.length;
    }

    if (lastIndex < text.length) {
      tokens.push({ text: text.slice(lastIndex), ref: null });
    }
    return tokens.length > 0 ? tokens : [{ text, ref: null }];
  }
}
