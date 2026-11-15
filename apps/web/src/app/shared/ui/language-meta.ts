export interface LanguageMeta {
  code: string;
  englishName: string;
  nativeName: string;
}

export const SUPPORTED_LANGUAGES: Readonly<Record<string, LanguageMeta>> = {
  all: { code: 'All', englishName: 'All Languages', nativeName: 'All' },
  en: { code: 'en', englishName: 'English', nativeName: 'English' },
  ta: { code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்' },
  hi: { code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी' },
  te: { code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు' },
  kn: { code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ' },
  ml: { code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം' },
  gu: { code: 'gu', englishName: 'Gujarati', nativeName: 'ગુજરાતી' },
  mr: { code: 'mr', englishName: 'Marathi', nativeName: 'मराठी' },
  bn: { code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা' },
  pa: { code: 'pa', englishName: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ' },
  ne: { code: 'ne', englishName: 'Nepali', nativeName: 'नेपाली' },
  de: { code: 'de', englishName: 'German', nativeName: 'Deutsch' },
  ro: { code: 'ro', englishName: 'Romanian', nativeName: 'Română' },
  pt: { code: 'pt', englishName: 'Portuguese', nativeName: 'Português' },
  si: { code: 'si', englishName: 'Sinhala', nativeName: 'සිංහල' },
  es: { code: 'es', englishName: 'Spanish', nativeName: 'Español' },
  fr: { code: 'fr', englishName: 'French', nativeName: 'Français' },
  it: { code: 'it', englishName: 'Italian', nativeName: 'Italiano' },
  pl: { code: 'pl', englishName: 'Polish', nativeName: 'Polski' },
  ru: { code: 'ru', englishName: 'Russian', nativeName: 'Русский' },
  hu: { code: 'hu', englishName: 'Hungarian', nativeName: 'Magyar' },
  mg: { code: 'mg', englishName: 'Malagasy', nativeName: 'Malagasy' },
  ja: { code: 'ja', englishName: 'Japanese', nativeName: '日本語' },
  ko: { code: 'ko', englishName: 'Korean', nativeName: '한국어' },
};

export function canonicalLanguageCode(raw?: string): string {
  const clean = (raw ?? 'en').trim().toLowerCase();
  if (!clean) return 'en';
  if (clean === 'all') return 'All';
  if (SUPPORTED_LANGUAGES[clean]) return clean;
  for (const [code, meta] of Object.entries(SUPPORTED_LANGUAGES)) {
    if (
      meta.englishName.toLowerCase() === clean ||
      meta.nativeName.toLowerCase() === clean
    ) {
      return code;
    }
  }
  return clean;
}

export function languageMetaFromCode(code: string): LanguageMeta {
  const lower = code.trim().toLowerCase();
  return (
    SUPPORTED_LANGUAGES[lower] ?? {
      code: lower,
      englishName: code.toUpperCase(),
      nativeName: '',
    }
  );
}

export function countNoun(pluralNoun: string, count: number): string {
  if (count === 1 && pluralNoun.length > 1 && pluralNoun.endsWith('s')) {
    return pluralNoun.slice(0, -1);
  }
  return pluralNoun;
}
