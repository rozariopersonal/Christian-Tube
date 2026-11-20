export interface ParsedBibleRef {
  bookNumber: number;
  bookName: string;
  chapter: number;
  verse: number | null;
  endVerse: number | null;
}

export interface NormalizedBibleQuery {
  normalizedQuery: string;
  directRef: ParsedBibleRef | null;
}

interface BookSpec {
  b: number;
  name: string;
  aliases: string[];
}

const CANONICAL_BOOKS: readonly BookSpec[] = [
  { b: 1, name: 'Genesis', aliases: ['gen', 'ge', 'gn'] },
  { b: 2, name: 'Exodus', aliases: ['exod', 'exo', 'ex'] },
  { b: 3, name: 'Leviticus', aliases: ['lev', 'le', 'lv'] },
  { b: 4, name: 'Numbers', aliases: ['num', 'nu', 'nm'] },
  { b: 5, name: 'Deuteronomy', aliases: ['deut', 'deu', 'dt'] },
  { b: 6, name: 'Joshua', aliases: ['josh', 'jos'] },
  { b: 7, name: 'Judges', aliases: ['judg', 'jdg'] },
  { b: 8, name: 'Ruth', aliases: ['rut'] },
  { b: 9, name: '1 Samuel', aliases: ['1 sam', '1sam', '1sa'] },
  { b: 10, name: '2 Samuel', aliases: ['2 sam', '2sam', '2sa'] },
  { b: 11, name: '1 Kings', aliases: ['1 kgs', '1 ki', '1kings', '1kgs', '1ki'] },
  { b: 12, name: '2 Kings', aliases: ['2 kgs', '2 ki', '2kings', '2kgs', '2ki'] },
  { b: 13, name: '1 Chronicles', aliases: ['1 chron', '1 chr', '1ch', '1chron'] },
  { b: 14, name: '2 Chronicles', aliases: ['2 chron', '2 chr', '2ch', '2chron'] },
  { b: 15, name: 'Ezra', aliases: ['ezr'] },
  { b: 16, name: 'Nehemiah', aliases: ['neh', 'ne'] },
  { b: 17, name: 'Esther', aliases: ['esth', 'est'] },
  { b: 18, name: 'Job', aliases: ['jb'] },
  { b: 19, name: 'Psalms', aliases: ['psalm', 'ps', 'psa', 'pss'] },
  { b: 20, name: 'Proverbs', aliases: ['prov', 'pro', 'prv'] },
  { b: 21, name: 'Ecclesiastes', aliases: ['eccl', 'ecc', 'eccles'] },
  { b: 22, name: 'Song of Solomon', aliases: ['song of songs', 'song', 'sos', 'sng', 'canticles'] },
  { b: 23, name: 'Isaiah', aliases: ['isa'] },
  { b: 24, name: 'Jeremiah', aliases: ['jer'] },
  { b: 25, name: 'Lamentations', aliases: ['lam'] },
  { b: 26, name: 'Ezekiel', aliases: ['ezek', 'ezk'] },
  { b: 27, name: 'Daniel', aliases: ['dan', 'dn'] },
  { b: 28, name: 'Hosea', aliases: ['hos'] },
  { b: 29, name: 'Joel', aliases: ['jol'] },
  { b: 30, name: 'Amos', aliases: ['am'] },
  { b: 31, name: 'Obadiah', aliases: ['obad', 'oba'] },
  { b: 32, name: 'Jonah', aliases: ['jon'] },
  { b: 33, name: 'Micah', aliases: ['mic'] },
  { b: 34, name: 'Nahum', aliases: ['nah', 'nam'] },
  { b: 35, name: 'Habakkuk', aliases: ['hab'] },
  { b: 36, name: 'Zephaniah', aliases: ['zeph', 'zep'] },
  { b: 37, name: 'Haggai', aliases: ['hag'] },
  { b: 38, name: 'Zechariah', aliases: ['zech', 'zec'] },
  { b: 39, name: 'Malachi', aliases: ['mal'] },
  { b: 40, name: 'Matthew', aliases: ['matt', 'mt'] },
  { b: 41, name: 'Mark', aliases: ['mrk', 'mk'] },
  { b: 42, name: 'Luke', aliases: ['luk', 'lk'] },
  { b: 43, name: 'John', aliases: ['jhn', 'jn'] },
  { b: 44, name: 'Acts', aliases: ['act'] },
  { b: 45, name: 'Romans', aliases: ['rom', 'ro', 'rm'] },
  { b: 46, name: '1 Corinthians', aliases: ['1 cor', '1cor', '1co'] },
  { b: 47, name: '2 Corinthians', aliases: ['2 cor', '2cor', '2co'] },
  { b: 48, name: 'Galatians', aliases: ['gal', 'ga'] },
  { b: 49, name: 'Ephesians', aliases: ['eph'] },
  { b: 50, name: 'Philippians', aliases: ['phil', 'php'] },
  { b: 51, name: 'Colossians', aliases: ['col'] },
  { b: 52, name: '1 Thessalonians', aliases: ['1 thess', '1thes', '1th'] },
  { b: 53, name: '2 Thessalonians', aliases: ['2 thess', '2thes', '2th'] },
  { b: 54, name: '1 Timothy', aliases: ['1 tim', '1tim', '1ti'] },
  { b: 55, name: '2 Timothy', aliases: ['2 tim', '2tim', '2ti'] },
  { b: 56, name: 'Titus', aliases: ['tit'] },
  { b: 57, name: 'Philemon', aliases: ['phlm', 'phm'] },
  { b: 58, name: 'Hebrews', aliases: ['heb'] },
  { b: 59, name: 'James', aliases: ['jas', 'jm'] },
  { b: 60, name: '1 Peter', aliases: ['1 pet', '1pet', '1pe', '1pt'] },
  { b: 61, name: '2 Peter', aliases: ['2 pet', '2pet', '2pe', '2pt'] },
  { b: 62, name: '1 John', aliases: ['1 jn', '1jn', '1jo'] },
  { b: 63, name: '2 John', aliases: ['2 jn', '2jn', '2jo'] },
  { b: 64, name: '3 John', aliases: ['3 jn', '3jn', '3jo'] },
  { b: 65, name: 'Jude', aliases: ['jud'] },
  { b: 66, name: 'Revelation', aliases: ['rev', 're', 'revelations'] },
];

const EXACT_BOOK_LOOKUP = new Map<string, { bookNumber: number; bookName: string }>();
for (const spec of CANONICAL_BOOKS) {
  EXACT_BOOK_LOOKUP.set(spec.name.toLowerCase(), { bookNumber: spec.b, bookName: spec.name });
  for (const alias of spec.aliases) {
    EXACT_BOOK_LOOKUP.set(alias.toLowerCase(), { bookNumber: spec.b, bookName: spec.name });
  }
}

const ONES = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen',
];
const TENS = [
  '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
];
const EXACT_LARGE_NUMBERS: Record<number, string> = {
  1000: 'one thousand',
  2000: 'two thousand',
  3000: 'three thousand',
  4000: 'four thousand',
  5000: 'five thousand',
  7000: 'seven thousand',
  10000: 'ten thousand',
  12000: 'twelve thousand',
  144000: 'one hundred forty-four thousand',
};

export function damerauLevenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;

  const dp: number[][] = Array.from({ length: m + 1 }, () =>
    new Array<number>(n + 1).fill(0),
  );
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let val = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        val = Math.min(val, dp[i - 2][j - 2] + 1);
      }
      dp[i][j] = val;
    }
  }
  return dp[m][n];
}

function normalizeBookToken(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/\./g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:iii|3rd)\b/, '3')
    .replace(/^(?:ii|2nd)\b/, '2')
    .replace(/^(?:i|1st)\b/, '1')
    .replace(/^([123])\s+/, '$1 ');
}

function allowedTyposForLength(len: number): number {
  if (len <= 4) return 0;
  if (len <= 7) return 1;
  return 2;
}

/**
 * Resolves a canonical or misspelled Bible book phrase (e.g. "mathew",
 * "1 corintians", "revelations") using length-scaled edit distance so short
 * English words ("for", "had", "join") never misfire.
 */
export function resolveBookCandidate(
  rawBookPhrase: string,
): { bookNumber: number; bookName: string } | null {
  const norm = normalizeBookToken(rawBookPhrase);
  if (!norm) return null;

  const exact = EXACT_BOOK_LOOKUP.get(norm);
  if (exact) return exact;

  const numPrefix = norm.match(/^([123])\s+(.+)$/);
  const ord = numPrefix ? numPrefix[1] : '';
  const word = (numPrefix ? numPrefix[2] : norm).trim();
  const maxDist = allowedTyposForLength(word.length);
  if (maxDist === 0) return null;

  let best: { bookNumber: number; bookName: string } | null = null;
  let bestDist = maxDist + 1;

  for (const spec of CANONICAL_BOOKS) {
    const specParts = spec.name.toLowerCase().match(/^([123])\s+(.+)$/);
    const specOrd = specParts ? specParts[1] : '';
    const specWord = specParts ? specParts[2] : spec.name.toLowerCase();
    if (ord !== specOrd) continue;

    const d = Math.min(
      damerauLevenshtein(word, specWord),
      specWord.length > 4 && specWord.endsWith('s')
        ? damerauLevenshtein(word, specWord.slice(0, -1))
        : maxDist + 1,
    );
    if (d <= maxDist && d < bestDist) {
      bestDist = d;
      best = { bookNumber: spec.b, bookName: spec.name };
      if (d === 1) break;
    }
  }

  return best;
}

export function numberToWords(n: number): string | null {
  if (!Number.isInteger(n) || n < 0) return null;
  if (EXACT_LARGE_NUMBERS[n]) return EXACT_LARGE_NUMBERS[n];
  if (n >= 1000) return null;
  if (n < 20) return ONES[n];
  if (n < 100) {
    const rem = n % 10;
    return rem === 0
      ? TENS[Math.floor(n / 10)]
      : `${TENS[Math.floor(n / 10)]}-${ONES[rem]}`;
  }
  const hundreds = Math.floor(n / 100);
  const rem = n % 100;
  return rem === 0
    ? `${ONES[hundreds]} hundred`
    : `${ONES[hundreds]} hundred ${numberToWords(rem)}`;
}

const REFERENCE_CANDIDATE_RE =
  /\b((?:(?:[123](?:st|nd|rd)?|I{1,3})\.?\s+)?[A-Za-z]{3,20}(?:\s+of\s+(?:solomon|songs))?)\s+(\d{1,3})(?:[:.]\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?)?\b/gi;

/**
 * Normalizes fuzzy book-name citations ("mathew 6:33" -> "Matthew 6:33",
 * "1 corintians 13:4" -> "1 Corinthians 13:4"), protects all digits inside
 * references, and expands standalone cardinal digits ("10" -> "ten", "5000" ->
 * "five thousand") to match spelled-out WEB Bible phrasing.
 */
export function normalizeBibleQuery(rawQuery: string): NormalizedBibleQuery {
  const input = rawQuery.trim();
  if (!input) return { normalizedQuery: '', directRef: null };

  let directRef: ParsedBibleRef | null = null;
  const protectedTokens: string[] = [];
  const placeholderFor = (text: string) => {
    const idx = protectedTokens.push(text) - 1;
    return `__REF_TOK_${idx}__`;
  };

  let working = input.replace(
    REFERENCE_CANDIDATE_RE,
    (full, bookRaw: string, chRaw: string, vRaw?: string, endVRaw?: string) => {
      const resolved = resolveBookCandidate(bookRaw);
      if (!resolved) return full;

      const chapter = parseInt(chRaw, 10);
      const verse = vRaw ? parseInt(vRaw, 10) : null;
      const endVerse = endVRaw ? parseInt(endVRaw, 10) : null;
      if (chapter < 1 || chapter > 150) return full;

      if (!directRef) {
        directRef = {
          bookNumber: resolved.bookNumber,
          bookName: resolved.bookName,
          chapter,
          verse,
          endVerse,
        };
      }

      const formatted =
        verse != null
          ? endVerse != null
            ? `${resolved.bookName} ${chapter}:${verse}-${endVerse}`
            : `${resolved.bookName} ${chapter}:${verse}`
          : `${resolved.bookName} ${chapter}`;
      return placeholderFor(formatted);
    },
  );

  // Also protect bare chapter:verse patterns without a book prefix (e.g. "3:16").
  working = working.replace(/\b\d{1,3}:\d{1,3}(?:[-–]\d{1,3})?\b/g, (m) =>
    placeholderFor(m),
  );

  // Replace standalone cardinal digits outside references with spelled-out words.
  working = working.replace(/\b(\d+)\b(?!\s*(?:st|nd|rd|th|am|pm)\b)/gi, (full, numStr: string, offset: number, src: string) => {
    const before = offset > 0 ? src[offset - 1] : ' ';
    const after = offset + full.length < src.length ? src[offset + full.length] : ' ';
    if (before === '_' || after === '_' || before === ':' || after === ':') {
      return full;
    }
    const val = parseInt(numStr, 10);
    return numberToWords(val) ?? full;
  });

  const normalizedQuery = working
    .replace(/__REF_TOK_(\d+)__/g, (_, i: string) => protectedTokens[Number(i)] || '')
    .replace(/\s+/g, ' ')
    .trim();

  return { normalizedQuery, directRef };
}

/**
 * Checks whether [term] matches a word in [lowerText], allowing 1 typo for
 * longer content words (e.g. "lepors" matching "lepers").
 */
export function fuzzyWordMatch(term: string, lowerText: string): boolean {
  if (!term || !lowerText) return false;
  if (new RegExp(`\\b${term}`).test(lowerText)) return true;
  if (term.length < 5) return false;

  const tokens = lowerText.split(/[^a-z0-9]+/);
  const firstChar = term[0];
  for (const tok of tokens) {
    if (!tok || tok[0] !== firstChar) continue;
    if (Math.abs(tok.length - term.length) > 1) continue;
    if (damerauLevenshtein(term, tok) <= 1) return true;
  }
  return false;
}
