import fs from 'fs';
import path from 'path';
import { AppConfig, InputChapter, VerseItem } from './types.js';

export interface BookInfo {
  bookNumber: number;
  name: string;
  chapters: number;
}

// Standard English & Tamil 66 Bible Books fallback table
export const STANDARD_BOOKS: Array<{ bookNumber: number; nameEn: string; nameTa: string; chapters: number }> = [
  { bookNumber: 1, nameEn: 'Genesis', nameTa: 'ஆதியாகமம்', chapters: 50 },
  { bookNumber: 2, nameEn: 'Exodus', nameTa: 'யாத்திராகமம்', chapters: 40 },
  { bookNumber: 3, nameEn: 'Leviticus', nameTa: 'லேவியராகமம்', chapters: 27 },
  { bookNumber: 4, nameEn: 'Numbers', nameTa: 'எண்ணாகமம்', chapters: 36 },
  { bookNumber: 5, nameEn: 'Deuteronomy', nameTa: 'உபாகமம்', chapters: 34 },
  { bookNumber: 6, nameEn: 'Joshua', nameTa: 'யோசுவா', chapters: 24 },
  { bookNumber: 7, nameEn: 'Judges', nameTa: 'நியாயாதிபதிகள்', chapters: 21 },
  { bookNumber: 8, nameEn: 'Ruth', nameTa: 'ரூத்', chapters: 4 },
  { bookNumber: 9, nameEn: '1 Samuel', nameTa: '1 சாமுவேல்', chapters: 31 },
  { bookNumber: 10, nameEn: '2 Samuel', nameTa: '2 சாமுவேல்', chapters: 24 },
  { bookNumber: 11, nameEn: '1 Kings', nameTa: '1 இராஜாக்கள்', chapters: 22 },
  { bookNumber: 12, nameEn: '2 Kings', nameTa: '2 இராஜாக்கள்', chapters: 25 },
  { bookNumber: 13, nameEn: '1 Chronicles', nameTa: '1 நாளாகமம்', chapters: 29 },
  { bookNumber: 14, nameEn: '2 Chronicles', nameTa: '2 நாளாகமம்', chapters: 36 },
  { bookNumber: 15, nameEn: 'Ezra', nameTa: 'எஸ்றா', chapters: 10 },
  { bookNumber: 16, nameEn: 'Nehemiah', nameTa: 'நெகேமியா', chapters: 13 },
  { bookNumber: 17, nameEn: 'Esther', nameTa: 'எஸ்தர்', chapters: 10 },
  { bookNumber: 18, nameEn: 'Job', nameTa: 'யோபு', chapters: 42 },
  { bookNumber: 19, nameEn: 'Psalms', nameTa: 'சங்கீதம்', chapters: 150 },
  { bookNumber: 20, nameEn: 'Proverbs', nameTa: 'நீதிமொழிகள்', chapters: 31 },
  { bookNumber: 21, nameEn: 'Ecclesiastes', nameTa: 'பிரசங்கி', chapters: 12 },
  { bookNumber: 22, nameEn: 'Song of Solomon', nameTa: 'உன்னதப்பாட்டு', chapters: 8 },
  { bookNumber: 23, nameEn: 'Isaiah', nameTa: 'ஏசாயா', chapters: 66 },
  { bookNumber: 24, nameEn: 'Jeremiah', nameTa: 'எரேமியா', chapters: 52 },
  { bookNumber: 25, nameEn: 'Lamentations', nameTa: 'புலம்பல்', chapters: 5 },
  { bookNumber: 26, nameEn: 'Ezekiel', nameTa: 'எசேக்கியேல்', chapters: 48 },
  { bookNumber: 27, nameEn: 'Daniel', nameTa: 'தானியேல்', chapters: 12 },
  { bookNumber: 28, nameEn: 'Hosea', nameTa: 'ஓசியா', chapters: 14 },
  { bookNumber: 29, nameEn: 'Joel', nameTa: 'யோவேல்', chapters: 3 },
  { bookNumber: 30, nameEn: 'Amos', nameTa: 'ஆமோஸ்', chapters: 9 },
  { bookNumber: 31, nameEn: 'Obadiah', nameTa: 'ஒபதியா', chapters: 1 },
  { bookNumber: 32, nameEn: 'Jonah', nameTa: 'யோனா', chapters: 4 },
  { bookNumber: 33, nameEn: 'Micah', nameTa: 'மீகா', chapters: 7 },
  { bookNumber: 34, nameEn: 'Nahum', nameTa: 'நாகூம்', chapters: 3 },
  { bookNumber: 35, nameEn: 'Habakkuk', nameTa: 'ஆபகூக்', chapters: 3 },
  { bookNumber: 36, nameEn: 'Zephaniah', nameTa: 'செப்பனியா', chapters: 3 },
  { bookNumber: 37, nameEn: 'Haggai', nameTa: 'ஆகாய்', chapters: 2 },
  { bookNumber: 38, nameEn: 'Zechariah', nameTa: 'சகரியா', chapters: 14 },
  { bookNumber: 39, nameEn: 'Malachi', nameTa: 'மல்கியா', chapters: 4 },
  { bookNumber: 40, nameEn: 'Matthew', nameTa: 'மத்தேயு', chapters: 28 },
  { bookNumber: 41, nameEn: 'Mark', nameTa: 'மாற்கு', chapters: 16 },
  { bookNumber: 42, nameEn: 'Luke', nameTa: 'லூக்கா', chapters: 24 },
  { bookNumber: 43, nameEn: 'John', nameTa: 'யோவான்', chapters: 21 },
  { bookNumber: 44, nameEn: 'Acts', nameTa: 'அப்போஸ்தலர் நடபடிகள்', chapters: 28 },
  { bookNumber: 45, nameEn: 'Romans', nameTa: 'ரோமர்', chapters: 16 },
  { bookNumber: 46, nameEn: '1 Corinthians', nameTa: '1 கொரிந்தியர்', chapters: 16 },
  { bookNumber: 47, nameEn: '2 Corinthians', nameTa: '2 கொரிந்தியர்', chapters: 13 },
  { bookNumber: 48, nameEn: 'Galatians', nameTa: 'கலாத்தியர்', chapters: 6 },
  { bookNumber: 49, nameEn: 'Ephesians', nameTa: 'எபேசியர்', chapters: 6 },
  { bookNumber: 50, nameEn: 'Philippians', nameTa: 'பிலிப்பியர்', chapters: 4 },
  { bookNumber: 51, nameEn: 'Colossians', nameTa: 'கொலோசெயர்', chapters: 4 },
  { bookNumber: 52, nameEn: '1 Thessalonians', nameTa: '1 தெசலோனிக்கேயர்', chapters: 5 },
  { bookNumber: 53, nameEn: '2 Thessalonians', nameTa: '2 தெசலோனிக்கேயர்', chapters: 3 },
  { bookNumber: 54, nameEn: '1 Timothy', nameTa: '1 தீமோத்தேயு', chapters: 6 },
  { bookNumber: 55, nameEn: '2 Timothy', nameTa: '2 தீமோத்தேயு', chapters: 4 },
  { bookNumber: 56, nameEn: 'Titus', nameTa: 'தீத்து', chapters: 3 },
  { bookNumber: 57, nameEn: 'Philemon', nameTa: 'பிலேமோன்', chapters: 1 },
  { bookNumber: 58, nameEn: 'Hebrews', nameTa: 'எபிரெயர்', chapters: 13 },
  { bookNumber: 59, nameEn: 'James', nameTa: 'யாக்கோபு', chapters: 5 },
  { bookNumber: 60, nameEn: '1 Peter', nameTa: '1 பேதுரு', chapters: 5 },
  { bookNumber: 61, nameEn: '2 Peter', nameTa: '2 பேதுரு', chapters: 3 },
  { bookNumber: 62, nameEn: '1 John', nameTa: '1 யோவான்', chapters: 5 },
  { bookNumber: 63, nameEn: '2 John', nameTa: '2 யோவான்', chapters: 1 },
  { bookNumber: 64, nameEn: '3 John', nameTa: '3 யோவான்', chapters: 1 },
  { bookNumber: 65, nameEn: 'Jude', nameTa: 'யூதா', chapters: 1 },
  { bookNumber: 66, nameEn: 'Revelation', nameTa: 'வெளிப்படுத்தின விசேஷம்', chapters: 22 },
];

export function getBookSlug(bookNumber: number, nameEn: string): string {
  const numStr = String(bookNumber).padStart(2, '0');
  const cleanName = nameEn.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return `${numStr}_${cleanName}`;
}

export class BibleReader {
  private config: AppConfig;

  constructor(config: AppConfig) {
    this.config = config;
  }

  /** Resolves the configured dir for a source version key (e.g. 'web', 'ta_ovbsi'). */
  public sourceDir(versionKey: string): string | null {
    const dir = this.config.bible_source_dirs[versionKey];
    return dir && fs.existsSync(dir) ? dir : null;
  }

  private loadBooksFromDir(dir: string): BookInfo[] {
    const booksPath = path.join(dir, 'books.json');
    if (fs.existsSync(booksPath)) {
      try {
        const raw = JSON.parse(fs.readFileSync(booksPath, 'utf8'));
        if (Array.isArray(raw) && raw.length > 0) {
          return raw.map((b) => ({
            bookNumber: Number(b.bookNumber ?? b.book ?? 0),
            name: String(b.name ?? b.nameEn ?? ''),
            chapters: Number(b.chapters ?? 0),
          })).filter((b) => b.bookNumber >= 1 && b.bookNumber <= 66 && b.chapters > 0);
        }
      } catch {
        // fall through to standard catalog
      }
    }
    return [];
  }

  public getBooks(versionKey?: string): BookInfo[] {
    if (versionKey) {
      const dir = this.sourceDir(versionKey);
      if (dir) {
        const fromJson = this.loadBooksFromDir(dir);
        if (fromJson.length > 0) return fromJson;
      }
    }
    return STANDARD_BOOKS.map((b) => ({
      bookNumber: b.bookNumber,
      name: b.nameEn,
      chapters: b.chapters,
    }));
  }

  public findBook(query: string | number): (BookInfo & { nameEn: string; nameTa: string; slug: string }) | undefined {
    const qStr = String(query).trim().toLowerCase();
    const qNum = parseInt(qStr, 10);

    for (const b of STANDARD_BOOKS) {
      const slug = getBookSlug(b.bookNumber, b.nameEn);
      if (!isNaN(qNum) && b.bookNumber === qNum) {
        return { ...b, name: b.nameTa, slug };
      }
      if (
        b.nameEn.toLowerCase() === qStr ||
        b.nameTa.toLowerCase() === qStr ||
        slug === qStr ||
        b.nameEn.toLowerCase().replace(/\s+/g, '') === qStr.replace(/\s+/g, '')
      ) {
        return { ...b, name: b.nameTa, slug };
      }
    }
    return undefined;
  }

  public getBookName(bookNumber: number, language?: string): string {
    const std = STANDARD_BOOKS.find((s) => s.bookNumber === bookNumber);
    if (!std) return `Book ${bookNumber}`;
    return language === 'ta' ? std.nameTa : std.nameEn;
  }

  /**
   * Reads a chapter from the JSON directory of a given source version
   * (e.g. 'web', 'ta_ovbsi', 'kjv').
   */
  public async getChapter(
    bookNumber: number,
    chapterNumber: number,
    versionKey?: string
  ): Promise<InputChapter | null> {
    const key = versionKey || Object.keys(this.config.bible_source_dirs)[0] || 'web';
    const dir = this.sourceDir(key);
    const bookName = this.getBookName(bookNumber, key === 'ta_ovbsi' ? 'ta' : 'en');

    if (dir) {
      const chapterJsonPath = path.join(dir, String(bookNumber), `${chapterNumber}.json`);
      if (fs.existsSync(chapterJsonPath)) {
        const raw = fs.readFileSync(chapterJsonPath, 'utf8');
        const versesRaw = JSON.parse(raw) as Array<{ verse: number; text: string }>;
        const verses: VerseItem[] = versesRaw.map((v) => ({
          verse: v.verse,
          text: (v.text || '').trim(),
        })).filter((v) => v.verse > 0 && v.text.length > 0);

        if (verses.length > 0) {
          return {
            version_id: this.config.version_id,
            source_version: key,
            book: bookNumber,
            book_name: bookName,
            chapter: chapterNumber,
            verses,
          };
        }
      }
    }

    return null;
  }

  /**
   * Returns a list of all chapter coordinates in the Bible (1,189 chapters).
   */
  public getAllChapters(): Array<{ book: number; chapter: number }> {
    const list: Array<{ book: number; chapter: number }> = [];
    for (const b of STANDARD_BOOKS) {
      for (let c = 1; c <= b.chapters; c++) {
        list.push({ book: b.bookNumber, chapter: c });
      }
    }
    return list;
  }
}