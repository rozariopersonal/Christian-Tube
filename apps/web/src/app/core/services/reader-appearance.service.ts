import { Injectable, computed, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../api/release-data.service';
import { AuthService } from '../auth/auth.service';
import { UserSyncService } from './user-sync.service';
import { AppConfig } from '../config/app-config';
import { ScreenClass } from '../layout/screen-class.service';

export type ReaderFontLanguageCode = 'en' | 'ta' | 'hi' | 'te' | 'ml' | 'kn';
export type ReaderFontSource = 'builtin' | 'ondemand' | 'system';

export interface ReaderFontLanguageMeta {
  code: ReaderFontLanguageCode;
  label: string;
  nativeLabel: string;
  sampleText: string;
}

export const READER_FONT_LANGUAGES: readonly ReaderFontLanguageMeta[] = [
  {
    code: 'en',
    label: 'English & Latin',
    nativeLabel: 'English',
    sampleText: 'In the beginning was the Word',
  },
  {
    code: 'ta',
    label: 'Tamil',
    nativeLabel: 'தமிழ்',
    sampleText: 'ஆதியிலே வார்த்தை இருந்தது',
  },
  {
    code: 'hi',
    label: 'Hindi & Devanagari',
    nativeLabel: 'हिन्दी',
    sampleText: 'आदि में वचन था',
  },
  {
    code: 'te',
    label: 'Telugu',
    nativeLabel: 'తెలుగు',
    sampleText: 'ఆదియందు వాక్యముండెను',
  },
  {
    code: 'ml',
    label: 'Malayalam',
    nativeLabel: 'മലയാളം',
    sampleText: 'ആദിയിൽ വചനം ഉണ്ടായിരുന്നു',
  },
  {
    code: 'kn',
    label: 'Kannada',
    nativeLabel: 'ಕನ್ನಡ',
    sampleText: 'ಆದಿಯಲ್ಲಿ ವಾಕ್ಯವಿತ್ತು',
  },
];

export interface ReaderFontOption {
  id: string;
  label: string;
  shortLabel?: string;
  subtitle?: string;
  cssFamily: string;
  fontFamily?: string;
  releaseFile?: string;
  language?: ReaderFontLanguageCode;
  source?: ReaderFontSource;
}

export interface ReaderFontGroup extends ReaderFontLanguageMeta {
  fonts: readonly ReaderFontOption[];
  onDemandCount: number;
  downloadedCount: number;
  systemCount: number;
}

export const READER_FONTS: readonly ReaderFontOption[] = [
  // ── Core & English / Latin Fonts ──────────────────────────────────────────
  {
    id: 'system',
    label: 'System Sans',
    shortLabel: 'System',
    subtitle: 'Default UI Sans',
    cssFamily: "'Inter', system-ui, sans-serif",
    language: 'en',
    source: 'builtin',
  },
  {
    id: 'literata',
    label: 'Literata (Serif)',
    shortLabel: 'Literata',
    subtitle: 'Editorial Book Serif',
    cssFamily: "'Literata', 'Lora', Georgia, serif",
    fontFamily: 'Literata',
    releaseFile: 'Lora-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'merriweather',
    label: 'Merriweather (Serif)',
    shortLabel: 'Merriweather',
    subtitle: 'Bold Reading Serif',
    cssFamily: "'Merriweather', Georgia, serif",
    fontFamily: 'Merriweather',
    releaseFile: 'Merriweather-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'noto-tamil',
    label: 'Noto Sans Tamil',
    shortLabel: 'Noto Tamil',
    subtitle: 'Classic Tamil Literature',
    cssFamily: "'Noto Serif Tamil', 'Noto Sans Tamil', 'Inter', sans-serif",
    fontFamily: 'Noto Serif Tamil',
    releaseFile: 'Noto_Serif_Tamil-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },
  {
    id: 'system-serif',
    label: 'System Serif',
    shortLabel: 'Serif',
    subtitle: 'Classic OS Serif',
    cssFamily: "Georgia, 'Times New Roman', serif",
    language: 'en',
    source: 'builtin',
  },
  {
    id: 'lora',
    label: 'Lora (Serif)',
    shortLabel: 'Lora',
    subtitle: 'Warm Editorial',
    cssFamily: "'Lora', Georgia, serif",
    fontFamily: 'Lora',
    releaseFile: 'Lora-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'playfair',
    label: 'Playfair Display',
    shortLabel: 'Playfair',
    subtitle: 'Classic Serif',
    cssFamily: "'Playfair Display', Georgia, serif",
    fontFamily: 'Playfair Display',
    releaseFile: 'Playfair_Display-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'cormorant',
    label: 'Cormorant Garamond',
    shortLabel: 'Cormorant',
    subtitle: 'Regal Literature',
    cssFamily: "'Cormorant Garamond', Georgia, serif",
    fontFamily: 'Cormorant Garamond',
    releaseFile: 'Cormorant_Garamond-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'cinzel',
    label: 'Cinzel',
    shortLabel: 'Cinzel',
    subtitle: 'Monumental Roman',
    cssFamily: "'Cinzel', Georgia, serif",
    fontFamily: 'Cinzel',
    releaseFile: 'Cinzel-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'outfit',
    label: 'Outfit',
    shortLabel: 'Outfit',
    subtitle: 'Modern Clean Sans',
    cssFamily: "'Outfit', 'Inter', sans-serif",
    fontFamily: 'Outfit',
    releaseFile: 'Outfit-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'montserrat',
    label: 'Montserrat',
    shortLabel: 'Montserrat',
    subtitle: 'Geometric Sans',
    cssFamily: "'Montserrat', 'Inter', sans-serif",
    fontFamily: 'Montserrat',
    releaseFile: 'Montserrat-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'poppins',
    label: 'Poppins',
    shortLabel: 'Poppins',
    subtitle: 'Clean Geometric Sans',
    cssFamily: "'Poppins', 'Inter', sans-serif",
    fontFamily: 'Poppins',
    releaseFile: 'Poppins-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },
  {
    id: 'great-vibes',
    label: 'Great Vibes',
    shortLabel: 'Great Vibes',
    subtitle: 'Graceful Script',
    cssFamily: "'Great Vibes', Georgia, cursive",
    fontFamily: 'Great Vibes',
    releaseFile: 'Great_Vibes-Regular.ttf',
    language: 'en',
    source: 'ondemand',
  },

  // ── Tamil Reading Fonts (On-Demand) ───────────────────────────────────────
  {
    id: 'mukta-malar',
    label: 'Mukta Malar (முக்தா மலர்)',
    shortLabel: 'Mukta Malar',
    subtitle: 'Contemporary Tamil',
    cssFamily: "'Mukta Malar', 'Inter', sans-serif",
    fontFamily: 'Mukta Malar',
    releaseFile: 'Mukta_Malar-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },
  {
    id: 'catamaran',
    label: 'Catamaran (கட்டமரன்)',
    shortLabel: 'Catamaran',
    subtitle: 'Clean & Modern Tamil',
    cssFamily: "'Catamaran', 'Inter', sans-serif",
    fontFamily: 'Catamaran',
    releaseFile: 'Catamaran-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },
  {
    id: 'kavivanar',
    label: 'Kavivanar (கவிவாணர்)',
    shortLabel: 'Kavivanar',
    subtitle: 'Curved Devotional',
    cssFamily: "'Kavivanar', 'Inter', serif",
    fontFamily: 'Kavivanar',
    releaseFile: 'Kavivanar-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },
  {
    id: 'arima',
    label: 'Arima (அரிமா மதுரை)',
    shortLabel: 'Arima',
    subtitle: 'Graceful Calligraphy',
    cssFamily: "'Arima', 'Inter', serif",
    fontFamily: 'Arima',
    releaseFile: 'Arima-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },
  {
    id: 'coiny',
    label: 'Coiny (கோய்னி)',
    shortLabel: 'Coiny',
    subtitle: 'Bold Rounded Tamil',
    cssFamily: "'Coiny', 'Inter', sans-serif",
    fontFamily: 'Coiny',
    releaseFile: 'Coiny-Regular.ttf',
    language: 'ta',
    source: 'ondemand',
  },

  // ── Hindi & Devanagari Reading Fonts (On-Demand) ──────────────────────────
  {
    id: 'noto-serif-devanagari',
    label: 'Noto Serif Devanagari (नोटो सेरिफ़)',
    shortLabel: 'Noto Hindi',
    subtitle: 'Sacred Devanagari Serif',
    cssFamily: "'Noto Serif Devanagari', 'Inter', serif",
    fontFamily: 'Noto Serif Devanagari',
    releaseFile: 'Noto_Serif_Devanagari-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },
  {
    id: 'anek-devanagari',
    label: 'Anek Devanagari (अनेक)',
    shortLabel: 'Anek Hindi',
    subtitle: 'Contemporary Hindi',
    cssFamily: "'Anek Devanagari', 'Inter', sans-serif",
    fontFamily: 'Anek Devanagari',
    releaseFile: 'Anek_Devanagari-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },
  {
    id: 'rozha-one',
    label: 'Rozha One (रोज़ा वन)',
    shortLabel: 'Rozha One',
    subtitle: 'Dramatic Serif',
    cssFamily: "'Rozha One', 'Inter', serif",
    fontFamily: 'Rozha One',
    releaseFile: 'Rozha_One-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },
  {
    id: 'yatra-one',
    label: 'Yatra One (यात्रा वन)',
    shortLabel: 'Yatra One',
    subtitle: 'Devotional Display',
    cssFamily: "'Yatra One', 'Inter', serif",
    fontFamily: 'Yatra One',
    releaseFile: 'Yatra_One-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },
  {
    id: 'kalam',
    label: 'Kalam (कलम)',
    shortLabel: 'Kalam',
    subtitle: 'Warm Handwritten',
    cssFamily: "'Kalam', 'Inter', serif",
    fontFamily: 'Kalam',
    releaseFile: 'Kalam-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },
  {
    id: 'poppins-hi',
    label: 'Poppins Devanagari (पॉपिन्स)',
    shortLabel: 'Poppins Hi',
    subtitle: 'Clean Geometric',
    cssFamily: "'Poppins', 'Inter', sans-serif",
    fontFamily: 'Poppins',
    releaseFile: 'Poppins-Regular.ttf',
    language: 'hi',
    source: 'ondemand',
  },

  // ── Telugu Reading Fonts (On-Demand) ──────────────────────────────────────
  {
    id: 'noto-serif-telugu',
    label: 'Noto Serif Telugu (నోటో సెరిఫ్)',
    shortLabel: 'Noto Telugu',
    subtitle: 'Sacred Literature Serif',
    cssFamily: "'Noto Serif Telugu', 'Inter', serif",
    fontFamily: 'Noto Serif Telugu',
    releaseFile: 'Noto_Serif_Telugu-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },
  {
    id: 'mandali',
    label: 'Mandali (మండలి)',
    shortLabel: 'Mandali',
    subtitle: 'Clear Modern Telugu',
    cssFamily: "'Mandali', 'Inter', sans-serif",
    fontFamily: 'Mandali',
    releaseFile: 'Mandali-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },
  {
    id: 'suranna',
    label: 'Suranna (సూరన్న)',
    shortLabel: 'Suranna',
    subtitle: 'Classic Editorial',
    cssFamily: "'Suranna', 'Inter', serif",
    fontFamily: 'Suranna',
    releaseFile: 'Suranna-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },
  {
    id: 'ramabhadra',
    label: 'Ramabhadra (రామభద్ర)',
    shortLabel: 'Ramabhadra',
    subtitle: 'Bold Royal',
    cssFamily: "'Ramabhadra', 'Inter', sans-serif",
    fontFamily: 'Ramabhadra',
    releaseFile: 'Ramabhadra-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },
  {
    id: 'anek-telugu',
    label: 'Anek Telugu (అనేక్)',
    shortLabel: 'Anek Telugu',
    subtitle: 'Modern Display',
    cssFamily: "'Anek Telugu', 'Inter', sans-serif",
    fontFamily: 'Anek Telugu',
    releaseFile: 'Anek_Telugu-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },
  {
    id: 'gidugu',
    label: 'Gidugu (గిడుగు)',
    shortLabel: 'Gidugu',
    subtitle: 'Artistic Fluid',
    cssFamily: "'Gidugu', 'Inter', serif",
    fontFamily: 'Gidugu',
    releaseFile: 'Gidugu-Regular.ttf',
    language: 'te',
    source: 'ondemand',
  },

  // ── Malayalam Reading Fonts (On-Demand) ───────────────────────────────────
  {
    id: 'noto-serif-malayalam',
    label: 'Noto Serif Malayalam (നോട്ടോ സെരിഫ്)',
    shortLabel: 'Noto Malayalam',
    subtitle: 'Classic Sacred Text',
    cssFamily: "'Noto Serif Malayalam', 'Inter', serif",
    fontFamily: 'Noto Serif Malayalam',
    releaseFile: 'Noto_Serif_Malayalam-Regular.ttf',
    language: 'ml',
    source: 'ondemand',
  },
  {
    id: 'gayathri',
    label: 'Gayathri (ഗായത്രി)',
    shortLabel: 'Gayathri',
    subtitle: 'Contemporary Malayalam',
    cssFamily: "'Gayathri', 'Inter', sans-serif",
    fontFamily: 'Gayathri',
    releaseFile: 'Gayathri-Regular.ttf',
    language: 'ml',
    source: 'ondemand',
  },
  {
    id: 'manjari',
    label: 'Manjari (മഞ്ജരി)',
    shortLabel: 'Manjari',
    subtitle: 'Modern Clean',
    cssFamily: "'Manjari', 'Inter', sans-serif",
    fontFamily: 'Manjari',
    releaseFile: 'Manjari-Regular.ttf',
    language: 'ml',
    source: 'ondemand',
  },
  {
    id: 'anek-malayalam',
    label: 'Anek Malayalam (അനേക്)',
    shortLabel: 'Anek Malayalam',
    subtitle: 'Bold Display',
    cssFamily: "'Anek Malayalam', 'Inter', sans-serif",
    fontFamily: 'Anek Malayalam',
    releaseFile: 'Anek_Malayalam-Regular.ttf',
    language: 'ml',
    source: 'ondemand',
  },
  {
    id: 'chilanka',
    label: 'Chilanka (ചിലങ്ക)',
    shortLabel: 'Chilanka',
    subtitle: 'Handwritten Script',
    cssFamily: "'Chilanka', 'Inter', cursive",
    fontFamily: 'Chilanka',
    releaseFile: 'Chilanka-Regular.ttf',
    language: 'ml',
    source: 'ondemand',
  },

  // ── Kannada Reading Fonts (On-Demand) ─────────────────────────────────────
  {
    id: 'noto-serif-kannada',
    label: 'Noto Serif Kannada (ನೋಟೋ ಸೆರಿಫ್)',
    shortLabel: 'Noto Kannada',
    subtitle: 'Sacred Classic Serif',
    cssFamily: "'Noto Serif Kannada', 'Inter', serif",
    fontFamily: 'Noto Serif Kannada',
    releaseFile: 'Noto_Serif_Kannada-Regular.ttf',
    language: 'kn',
    source: 'ondemand',
  },
  {
    id: 'hubballi',
    label: 'Hubballi (ಹುಬ್ಬಳ್ಳಿ)',
    shortLabel: 'Hubballi',
    subtitle: 'Smooth Modern',
    cssFamily: "'Hubballi', 'Inter', sans-serif",
    fontFamily: 'Hubballi',
    releaseFile: 'Hubballi-Regular.ttf',
    language: 'kn',
    source: 'ondemand',
  },
  {
    id: 'baloo-tamma-2',
    label: 'Baloo Tamma 2 (ಬಾಲೂ ತಮ್ಮ ೨)',
    shortLabel: 'Baloo Tamma',
    subtitle: 'Warm Rounded',
    cssFamily: "'Baloo Tamma 2', 'Inter', sans-serif",
    fontFamily: 'Baloo Tamma 2',
    releaseFile: 'Baloo_Tamma_2-Regular.ttf',
    language: 'kn',
    source: 'ondemand',
  },
  {
    id: 'anek-kannada',
    label: 'Anek Kannada (ಅನೇಕ)',
    shortLabel: 'Anek Kannada',
    subtitle: 'Bold Display',
    cssFamily: "'Anek Kannada', 'Inter', sans-serif",
    fontFamily: 'Anek Kannada',
    releaseFile: 'Anek_Kannada-Regular.ttf',
    language: 'kn',
    source: 'ondemand',
  },
];

interface SystemFontCandidate {
  family: string;
  language: ReaderFontLanguageCode;
  subtitle: string;
}

const SYSTEM_FONT_CANDIDATES: readonly SystemFontCandidate[] = [
  // English & Latin OS fonts
  { family: 'Georgia', language: 'en', subtitle: 'System Serif' },
  { family: 'Palatino Linotype', language: 'en', subtitle: 'System Serif' },
  { family: 'Book Antiqua', language: 'en', subtitle: 'System Serif' },
  { family: 'Baskerville', language: 'en', subtitle: 'System Serif' },
  { family: 'Garamond', language: 'en', subtitle: 'System Serif' },
  { family: 'Times New Roman', language: 'en', subtitle: 'System Serif' },
  { family: 'Cambria', language: 'en', subtitle: 'System Serif' },
  { family: 'Constantia', language: 'en', subtitle: 'System Serif' },
  { family: 'Charter', language: 'en', subtitle: 'System Serif' },
  { family: 'Iowan Old Style', language: 'en', subtitle: 'System Serif' },
  { family: 'Hoefler Text', language: 'en', subtitle: 'System Serif' },
  { family: 'Segoe UI', language: 'en', subtitle: 'System Sans' },
  { family: 'Calibri', language: 'en', subtitle: 'System Sans' },
  { family: 'Candara', language: 'en', subtitle: 'System Sans' },
  { family: 'Optima', language: 'en', subtitle: 'System Sans' },
  { family: 'Verdana', language: 'en', subtitle: 'System Sans' },
  { family: 'Trebuchet MS', language: 'en', subtitle: 'System Sans' },

  // Tamil OS fonts
  { family: 'Latha', language: 'ta', subtitle: 'System Tamil' },
  { family: 'Vijaya', language: 'ta', subtitle: 'System Tamil' },
  { family: 'InaiMathi', language: 'ta', subtitle: 'System Tamil' },
  { family: 'Tamil Sangam MN', language: 'ta', subtitle: 'System Tamil' },
  { family: 'Tamil MN', language: 'ta', subtitle: 'System Tamil' },
  { family: 'Nirmala UI', language: 'ta', subtitle: 'System Indic' },
  { family: 'Lohit Tamil', language: 'ta', subtitle: 'System Tamil' },

  // Hindi / Devanagari OS fonts
  { family: 'Mangal', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Kokila', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Aparajita', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Utsaah', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Devanagari Sangam MN', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Devanagari MT', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Kohinoor Devanagari', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'ITF Devanagari', language: 'hi', subtitle: 'System Devanagari' },
  { family: 'Lohit Devanagari', language: 'hi', subtitle: 'System Devanagari' },

  // Telugu OS fonts
  { family: 'Gautami', language: 'te', subtitle: 'System Telugu' },
  { family: 'Vani', language: 'te', subtitle: 'System Telugu' },
  { family: 'Telugu Sangam MN', language: 'te', subtitle: 'System Telugu' },
  { family: 'Telugu MN', language: 'te', subtitle: 'System Telugu' },
  { family: 'Kohinoor Telugu', language: 'te', subtitle: 'System Telugu' },
  { family: 'Lohit Telugu', language: 'te', subtitle: 'System Telugu' },
  { family: 'Pothana2000', language: 'te', subtitle: 'System Telugu' },

  // Malayalam OS fonts
  { family: 'Kartika', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'Malayalam Sangam MN', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'Malayalam MN', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'AnjaliOldLipi', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'Rachana', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'Meera', language: 'ml', subtitle: 'System Malayalam' },
  { family: 'Lohit Malayalam', language: 'ml', subtitle: 'System Malayalam' },

  // Kannada OS fonts
  { family: 'Tunga', language: 'kn', subtitle: 'System Kannada' },
  { family: 'Kannada Sangam MN', language: 'kn', subtitle: 'System Kannada' },
  { family: 'Kannada MN', language: 'kn', subtitle: 'System Kannada' },
  { family: 'Kedage', language: 'kn', subtitle: 'System Kannada' },
  { family: 'Lohit Kannada', language: 'kn', subtitle: 'System Kannada' },
];

export function classifySystemFontLanguage(
  familyName: string,
  fullName = '',
): ReaderFontLanguageCode {
  const combined = `${familyName} ${fullName}`.toLowerCase();
  if (
    /\b(tamil|latha|vijaya|inaimathi|marutham|bamini|kovai|valluvar|chennai|madurai)\b/.test(
      combined,
    )
  ) {
    return 'ta';
  }
  if (
    /\b(devanagari|hindi|mangal|kokila|aparajita|utsaah|kruti|kalam|rozha|yatra|samanata|gargi|nakula|sahadeva|chandas)\b/.test(
      combined,
    )
  ) {
    return 'hi';
  }
  if (
    /\b(telugu|gautami|vani|pothana|vemana|mandali|suranna|ramabhadra|gidugu|mallanna|ntr|peddana)\b/.test(
      combined,
    )
  ) {
    return 'te';
  }
  if (
    /\b(malayalam|kartika|anjali|rachana|meera|gayathri|manjari|chilanka|dyuthi|keraleeyam|uroob|suruma)\b/.test(
      combined,
    )
  ) {
    return 'ml';
  }
  if (
    /\b(kannada|tunga|kedage|mallige|hubballi|baloo tamma| Gubbi|navilu)\b/i.test(
      combined,
    )
  ) {
    return 'kn';
  }
  return 'en';
}

export type ReaderPaperTheme = 'auto' | 'paper' | 'sepia' | 'night';
export type BibleReadingLayout = 'verses' | 'paragraph';
export type BookTextAlign = 'left' | 'justify';
export type BookMarginSize = 'narrow' | 'medium' | 'wide';

export interface PaperThemeOption {
  id: ReaderPaperTheme;
  label: string;
  swatchBg: string;
  swatchFg: string;
}

export const READER_PAPER_THEMES: readonly PaperThemeOption[] = [
  { id: 'auto', label: 'App Theme', swatchBg: 'var(--bg)', swatchFg: 'var(--on-surface)' },
  { id: 'paper', label: 'Paper', swatchBg: '#FAF8F5', swatchFg: '#1F2937' },
  { id: 'sepia', label: 'Sepia', swatchBg: '#F4ECD8', swatchFg: '#433422' },
  { id: 'night', label: 'Night', swatchBg: '#121620', swatchFg: '#E2E8F0' },
];

export interface SpacingPreset {
  id: string;
  label: string;
  value: number;
}

export const LINE_HEIGHT_PRESETS: readonly SpacingPreset[] = [
  { id: 'tight', label: 'Tight', value: 1.4 },
  { id: 'normal', label: 'Normal', value: 1.65 },
  { id: 'relaxed', label: 'Relaxed', value: 1.95 },
];

export const LETTER_SPACING_PRESETS: readonly SpacingPreset[] = [
  { id: 'tight', label: 'Tight', value: -0.02 },
  { id: 'normal', label: 'Normal', value: 0 },
  { id: 'wide', label: 'Wide', value: 0.04 },
];

const KEY_FONT_ID = 'reader_font_id';
const KEY_FONT_SIZE = 'reader_font_size';
const KEY_LINE_HEIGHT = 'reader_line_height';
const KEY_LETTER_SPACING = 'reader_letter_spacing';
const KEY_PRIMARY_BIBLE = 'primary_bible_version';
const KEY_PAPER_THEME = 'reader_paper_theme';
const KEY_BIBLE_LAYOUT = 'bible_reading_layout';
const KEY_BOOK_ALIGN = 'book_text_align';
const KEY_BOOK_MARGIN = 'book_margin_size';
const KEY_BOOK_COLUMNS = 'book_columns';
const KEY_SINGLE_COL_PAGINATED = 'reader_single_col_paginated';
const KEY_DOWNLOADED_FONTS = 'reader_downloaded_font_ids';
const KEY_LOCAL_SYSTEM_FONTS = 'reader_local_system_fonts';

@Injectable({ providedIn: 'root' })
export class ReaderAppearanceService {
  private readonly releases = inject(ReleaseDataService);
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly systemFonts = signal<readonly ReaderFontOption[]>(
    this.loadInitialSystemFonts(),
  );
  readonly downloadedFontIds = signal<ReadonlySet<string>>(
    this.readDownloadedFontIds(),
  );
  readonly scanningSystemFonts = signal<boolean>(false);

  readonly allFonts = computed<readonly ReaderFontOption[]>(() => [
    ...READER_FONTS,
    ...this.systemFonts(),
  ]);

  readonly fontId = signal<string>(this.readStr(KEY_FONT_ID, 'system'));
  readonly fontSize = signal<number>(this.readNum(KEY_FONT_SIZE, 17, 13, 28));
  readonly lineHeight = signal<number>(this.readNum(KEY_LINE_HEIGHT, 1.65, 1.3, 2.2));
  readonly letterSpacing = signal<number>(
    this.readNum(KEY_LETTER_SPACING, 0, -0.04, 0.12),
  );
  readonly primaryBibleVersion = signal<string>(
    this.readStr(KEY_PRIMARY_BIBLE, AppConfig.defaultBibleVersion),
  );
  readonly paperTheme = signal<ReaderPaperTheme>(
    this.readPaperTheme(),
  );
  readonly bibleLayout = signal<BibleReadingLayout>(
    this.readStr(KEY_BIBLE_LAYOUT, 'verses') === 'paragraph' ? 'paragraph' : 'verses',
  );
  readonly bookAlign = signal<BookTextAlign>(
    this.readStr(KEY_BOOK_ALIGN, 'left') === 'justify' ? 'justify' : 'left',
  );
  readonly bookMargin = signal<BookMarginSize>(this.readBookMargin());
  readonly bookColumns = signal<1 | 2 | 3>(this.readBookColumns());
  readonly singleColPaginated = signal<boolean>(
    this.readStr(KEY_SINGLE_COL_PAGINATED, '0') === '1',
  );

  readonly fontsByLanguage = computed<readonly ReaderFontGroup[]>(() => {
    const all = this.allFonts();
    const downloadedIds = this.downloadedFontIds();
    const loadedFamilies = this.releases.loadedFontFamilies();

    return READER_FONT_LANGUAGES.map((langMeta) => {
      const fonts = all.filter((f) => (f.language ?? 'en') === langMeta.code);
      let onDemandCount = 0;
      let downloadedCount = 0;
      let systemCount = 0;

      for (const f of fonts) {
        if (f.source === 'system') {
          systemCount++;
        } else if (f.releaseFile) {
          onDemandCount++;
          const family = this.resolveFontFamilyName(f);
          if (downloadedIds.has(f.id) || loadedFamilies.has(family)) {
            downloadedCount++;
          }
        }
      }

      return {
        ...langMeta,
        fonts,
        onDemandCount,
        downloadedCount,
        systemCount,
      };
    });
  });

  constructor() {
    const initialFont = this.allFonts().find((f) => f.id === this.fontId());
    if (initialFont?.releaseFile) {
      void this.downloadFont(initialFont.id);
    }
    for (const id of this.downloadedFontIds()) {
      const f = READER_FONTS.find((opt) => opt.id === id);
      if (f?.releaseFile) {
        void this.releases.loadFont(this.resolveFontFamilyName(f), f.releaseFile);
      }
    }
  }

  activeFont(): ReaderFontOption {
    return this.allFonts().find((f) => f.id === this.fontId()) ?? READER_FONTS[0];
  }

  setFont(id: string): void {
    const opt = this.allFonts().find((f) => f.id === id) ?? READER_FONTS[0];
    this.fontId.set(opt.id);
    this.writeStr(KEY_FONT_ID, opt.id);
    if (opt.releaseFile) {
      void this.downloadFont(opt.id);
    }
  }

  isFontDownloaded(fontOrId: ReaderFontOption | string): boolean {
    const opt =
      typeof fontOrId === 'string'
        ? this.allFonts().find((f) => f.id === fontOrId)
        : fontOrId;
    if (!opt) return false;
    if (!opt.releaseFile || opt.source === 'builtin' || opt.source === 'system') {
      return true;
    }
    const family = this.resolveFontFamilyName(opt);
    return (
      this.downloadedFontIds().has(opt.id) ||
      this.releases.loadedFontFamilies().has(family)
    );
  }

  isFontDownloading(fontOrId: ReaderFontOption | string): boolean {
    const opt =
      typeof fontOrId === 'string'
        ? this.allFonts().find((f) => f.id === fontOrId)
        : fontOrId;
    if (!opt?.releaseFile) return false;
    const family = this.resolveFontFamilyName(opt);
    return this.releases.loadingFontFamilies().has(family);
  }

  async downloadFont(fontId: string): Promise<boolean> {
    const opt = this.allFonts().find((f) => f.id === fontId);
    if (!opt?.releaseFile) return true;
    const family = this.resolveFontFamilyName(opt);
    const ok = await this.releases.loadFont(family, opt.releaseFile);
    if (ok) {
      const next = new Set(this.downloadedFontIds());
      next.add(opt.id);
      this.downloadedFontIds.set(next);
      this.writeDownloadedFontIds(next);
    }
    return ok;
  }

  async downloadLanguageFonts(lang: ReaderFontLanguageCode): Promise<void> {
    const targets = READER_FONTS.filter(
      (f) => (f.language ?? 'en') === lang && !!f.releaseFile,
    );
    await Promise.all(targets.map((f) => this.downloadFont(f.id)));
  }

  isLanguageDownloading(lang: ReaderFontLanguageCode): boolean {
    const loading = this.releases.loadingFontFamilies();
    return READER_FONTS.some(
      (f) =>
        (f.language ?? 'en') === lang &&
        !!f.releaseFile &&
        loading.has(this.resolveFontFamilyName(f)),
    );
  }

  canQueryLocalFonts(): boolean {
    return typeof window !== 'undefined' && 'queryLocalFonts' in window;
  }

  async scanLocalSystemFonts(): Promise<number> {
    if (!this.canQueryLocalFonts()) return this.systemFonts().length;
    this.scanningSystemFonts.set(true);
    try {
      const queryFn = (
        window as unknown as {
          queryLocalFonts?: () => Promise<
            Array<{ family: string; fullName?: string }>
          >;
        }
      ).queryLocalFonts;
      if (!queryFn) return this.systemFonts().length;

      const fontDataList = await queryFn.call(window);
      const existingFamilies = new Set(
        READER_FONTS.map((f) => this.resolveFontFamilyName(f).toLowerCase()),
      );
      const byKey = new Map<string, ReaderFontOption>();
      for (const cur of this.systemFonts()) {
        byKey.set(cur.id, cur);
      }

      for (const item of fontDataList) {
        const family = (item.family ?? '').trim();
        if (!family || family.startsWith('.')) continue;
        if (existingFamilies.has(family.toLowerCase())) continue;

        const lang = classifySystemFontLanguage(family, item.fullName ?? '');
        const slug = family.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        const id = `sys-${lang}-${slug}`;
        if (!byKey.has(id)) {
          byKey.set(id, {
            id,
            label: family,
            shortLabel: family,
            subtitle: 'Installed System Font',
            cssFamily: `'${family.replace(/'/g, "\\'")}', system-ui, sans-serif`,
            fontFamily: family,
            language: lang,
            source: 'system',
          });
        }
      }

      const merged = Array.from(byKey.values()).sort((a, b) =>
        a.label.localeCompare(b.label),
      );
      this.systemFonts.set(merged);
      this.writeStr(
        KEY_LOCAL_SYSTEM_FONTS,
        JSON.stringify(
          merged.map((f) => ({
            id: f.id,
            family: f.fontFamily ?? f.label,
            language: f.language ?? 'en',
            subtitle: f.subtitle ?? 'Installed System Font',
          })),
        ),
      );
      return merged.length;
    } catch {
      return this.systemFonts().length;
    } finally {
      this.scanningSystemFonts.set(false);
    }
  }

  setFontSize(size: number): void {
    const clamped = Math.min(28, Math.max(13, Math.round(size)));
    this.fontSize.set(clamped);
    this.writeStr(KEY_FONT_SIZE, String(clamped));
  }

  stepFontSize(delta: number): void {
    this.setFontSize(this.fontSize() + delta);
  }

  setLineHeight(lh: number): void {
    const raw = Number(lh);
    if (Number.isNaN(raw)) return;
    const clamped = Math.min(2.2, Math.max(1.3, Number(raw.toFixed(2))));
    this.lineHeight.set(clamped);
    this.writeStr(KEY_LINE_HEIGHT, String(clamped));
  }

  stepLineHeight(delta: number): void {
    this.setLineHeight(this.lineHeight() + delta);
  }

  setLetterSpacing(ls: number): void {
    const raw = Number(ls);
    if (Number.isNaN(raw)) return;
    const clamped = Math.min(0.12, Math.max(-0.04, Number(raw.toFixed(2))));
    const normalized = Object.is(clamped, -0) ? 0 : clamped;
    this.letterSpacing.set(normalized);
    this.writeStr(KEY_LETTER_SPACING, String(normalized));
  }

  stepLetterSpacing(delta: number): void {
    this.setLetterSpacing(this.letterSpacing() + delta);
  }

  formatLetterSpacing(val = this.letterSpacing()): string {
    if (Math.abs(val) < 0.005) return 'Normal (0em)';
    return `${val > 0 ? '+' : ''}${val.toFixed(2)}em`;
  }

  setPrimaryBibleVersion(version: string, sync = true): void {
    this.primaryBibleVersion.set(version);
    this.writeStr(KEY_PRIMARY_BIBLE, version);
    if (sync && this.auth.isAuthenticated()) {
      this.userSync.enqueuePreference('primaryBibleVersionId', version.toUpperCase());
    }
  }

  setPaperTheme(theme: ReaderPaperTheme): void {
    this.paperTheme.set(theme);
    this.writeStr(KEY_PAPER_THEME, theme);
  }

  setBibleLayout(layout: BibleReadingLayout): void {
    this.bibleLayout.set(layout);
    this.writeStr(KEY_BIBLE_LAYOUT, layout);
  }

  setBookAlign(align: BookTextAlign): void {
    this.bookAlign.set(align);
    this.writeStr(KEY_BOOK_ALIGN, align);
  }

  setBookMargin(margin: BookMarginSize): void {
    this.bookMargin.set(margin);
    this.writeStr(KEY_BOOK_MARGIN, margin);
  }

  setSingleColPaginated(enabled: boolean): void {
    this.singleColPaginated.set(enabled);
    this.writeStr(KEY_SINGLE_COL_PAGINATED, enabled ? '1' : '0');
  }

  toggleSingleColPaginated(): void {
    this.setSingleColPaginated(!this.singleColPaginated());
  }

  setBookColumns(cols: 1 | 2 | 3): void {
    this.bookColumns.set(cols);
    this.writeStr(KEY_BOOK_COLUMNS, String(cols));
  }

  effectiveColumns(screenClass: ScreenClass): 1 | 2 | 3 {
    if (screenClass === 'compact') return 1;
    const cols = this.bookColumns();
    if (screenClass === 'medium') return cols >= 2 ? 2 : 1;
    return cols;
  }

  private resolveFontFamilyName(opt: ReaderFontOption): string {
    if (opt.fontFamily) return opt.fontFamily;
    return opt.cssFamily.split(',')[0].replace(/['"]/g, '').trim();
  }

  private loadInitialSystemFonts(): ReaderFontOption[] {
    const byId = new Map<string, ReaderFontOption>();

    // 1. Hydrate previously scanned local system fonts
    try {
      const raw = localStorage.getItem(KEY_LOCAL_SYSTEM_FONTS);
      if (raw) {
        const parsed = JSON.parse(raw) as Array<{
          id: string;
          family: string;
          language: ReaderFontLanguageCode;
          subtitle?: string;
        }>;
        if (Array.isArray(parsed)) {
          for (const item of parsed) {
            if (item?.id && item?.family) {
              byId.set(item.id, {
                id: item.id,
                label: item.family,
                shortLabel: item.family,
                subtitle: item.subtitle ?? 'Installed System Font',
                cssFamily: `'${item.family.replace(/'/g, "\\'")}', system-ui, sans-serif`,
                fontFamily: item.family,
                language: item.language ?? 'en',
                source: 'system',
              });
            }
          }
        }
      }
    } catch {
      // ignore
    }

    // 2. Probe standard OS fonts per language via offscreen canvas
    for (const detected of this.detectInstalledSystemFonts()) {
      if (!byId.has(detected.id)) {
        byId.set(detected.id, detected);
      }
    }

    return Array.from(byId.values());
  }

  private detectInstalledSystemFonts(): ReaderFontOption[] {
    if (typeof document === 'undefined') return [];
    if (typeof navigator !== 'undefined' && /jsdom/i.test(navigator.userAgent)) {
      return [];
    }
    try {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) return [];

      const testText = 'mmmmmmmmmmlli1WW@#0123456789';
      const bases = ['monospace', 'sans-serif', 'serif'] as const;
      const baseWidths = new Map<string, number>();
      for (const base of bases) {
        ctx.font = `72px ${base}`;
        baseWidths.set(base, ctx.measureText(testText).width);
      }

      // If canvas measureText returns identical widths for all base generic families (e.g. headless stub), skip
      if (
        baseWidths.get('monospace') === baseWidths.get('sans-serif') &&
        baseWidths.get('sans-serif') === baseWidths.get('serif')
      ) {
        return [];
      }

      const detected: ReaderFontOption[] = [];
      for (const candidate of SYSTEM_FONT_CANDIDATES) {
        const isInstalled = bases.some((base) => {
          ctx.font = `72px '${candidate.family}', ${base}`;
          return ctx.measureText(testText).width !== baseWidths.get(base);
        });
        if (isInstalled) {
          const slug = candidate.family.toLowerCase().replace(/[^a-z0-9]+/g, '-');
          detected.push({
            id: `sys-${candidate.language}-${slug}`,
            label: `${candidate.family}`,
            shortLabel: candidate.family,
            subtitle: candidate.subtitle,
            cssFamily: `'${candidate.family}', system-ui, sans-serif`,
            fontFamily: candidate.family,
            language: candidate.language,
            source: 'system',
          });
        }
      }
      return detected;
    } catch {
      return [];
    }
  }

  private readDownloadedFontIds(): Set<string> {
    try {
      const raw = localStorage.getItem(KEY_DOWNLOADED_FONTS);
      if (!raw) return new Set();
      const parsed = JSON.parse(raw) as unknown;
      if (Array.isArray(parsed)) {
        return new Set(parsed.filter((x): x is string => typeof x === 'string'));
      }
    } catch {
      // ignore
    }
    return new Set();
  }

  private writeDownloadedFontIds(ids: ReadonlySet<string>): void {
    try {
      localStorage.setItem(KEY_DOWNLOADED_FONTS, JSON.stringify(Array.from(ids)));
    } catch {
      // ignore
    }
  }

  private readBookColumns(): 1 | 2 | 3 {
    const raw = this.readStr(KEY_BOOK_COLUMNS, '2');
    if (raw === '1') return 1;
    if (raw === '3') return 3;
    return 2;
  }

  private readBookMargin(): BookMarginSize {
    const val = this.readStr(KEY_BOOK_MARGIN, 'medium');
    if (val === 'narrow' || val === 'wide') return val;
    return 'medium';
  }

  private readPaperTheme(): ReaderPaperTheme {
    const val = this.readStr(KEY_PAPER_THEME, 'auto');
    if (val === 'paper' || val === 'sepia' || val === 'night') return val;
    return 'auto';
  }

  private readStr(key: string, fallback: string): string {
    try {
      return localStorage.getItem(key) ?? fallback;
    } catch {
      return fallback;
    }
  }

  private writeStr(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // ignore
    }
  }

  private readNum(key: string, fallback: number, min: number, max: number): number {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return fallback;
      const num = Number(raw);
      if (Number.isNaN(num)) return fallback;
      return Math.min(max, Math.max(min, num));
    } catch {
      return fallback;
    }
  }
}
