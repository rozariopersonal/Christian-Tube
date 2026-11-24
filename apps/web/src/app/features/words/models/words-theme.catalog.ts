export interface BackgroundPreset {
  id: string;
  name: string;
  darkColors: readonly string[];
  lightColors: readonly string[];
  defaultDarkText: string;
  defaultLightText: string;
  isGradient: boolean;
}

export interface ScriptureFontOption {
  id: string;
  name: string;
  subtitle: string;
  sampleGlyph: string;
  cssFamily: string;
  googleFontQuery: string;
  languageCode?: string;
}

export interface ScriptureColorOption {
  hex: string;
  name: string;
}

export const ENGLISH_FONTS: readonly ScriptureFontOption[] = [
  {
    id: 'Playfair',
    name: 'Playfair Display',
    subtitle: 'Classic Serif',
    sampleGlyph: 'Grace',
    cssFamily: "'Playfair Display', Georgia, serif",
    googleFontQuery: 'Playfair+Display:ital,wght@0,400;0,700;1,400;1,700',
  },
  {
    id: 'Cinzel',
    name: 'Cinzel',
    subtitle: 'Monumental Roman',
    sampleGlyph: 'Peace',
    cssFamily: "'Cinzel', Georgia, serif",
    googleFontQuery: 'Cinzel:wght@400;700',
  },
  {
    id: 'Cormorant',
    name: 'Cormorant',
    subtitle: 'Regal Literature',
    sampleGlyph: 'Hope',
    cssFamily: "'Cormorant Garamond', Georgia, serif",
    googleFontQuery: 'Cormorant+Garamond:ital,wght@0,400;0,700;1,400;1,700',
  },
  {
    id: 'Outfit',
    name: 'Outfit',
    subtitle: 'Modern Clean',
    sampleGlyph: 'Life',
    cssFamily: "'Outfit', system-ui, sans-serif",
    googleFontQuery: 'Outfit:wght@400;700',
  },
  {
    id: 'Lora',
    name: 'Lora',
    subtitle: 'Warm Editorial',
    sampleGlyph: 'Faith',
    cssFamily: "'Lora', Georgia, serif",
    googleFontQuery: 'Lora:ital,wght@0,400;0,700;1,400;1,700',
  },
  {
    id: 'Merriweather',
    name: 'Merriweather',
    subtitle: 'Bold Reading',
    sampleGlyph: 'Love',
    cssFamily: "'Merriweather', Georgia, serif",
    googleFontQuery: 'Merriweather:ital,wght@0,400;0,700;1,400;1,700',
  },
  {
    id: 'GreatVibes',
    name: 'Great Vibes',
    subtitle: 'Graceful Script',
    sampleGlyph: 'Light',
    cssFamily: "'Great Vibes', cursive",
    googleFontQuery: 'Great+Vibes',
  },
  {
    id: 'Montserrat',
    name: 'Montserrat',
    subtitle: 'Geometric Sans',
    sampleGlyph: 'Joy',
    cssFamily: "'Montserrat', system-ui, sans-serif",
    googleFontQuery: 'Montserrat:ital,wght@0,400;0,700;1,400;1,700',
  },
];

export const LANGUAGE_FONTS: Record<string, readonly ScriptureFontOption[]> = {
  tam: [
    {
      id: 'MuktaMalar',
      name: 'முக்தா மலர் (Mukta Malar)',
      subtitle: 'Contemporary Tamil',
      sampleGlyph: 'அன்பு',
      cssFamily: "'Mukta Malar', sans-serif",
      googleFontQuery: 'Mukta+Malar:wght@400;700',
      languageCode: 'tam',
    },
    {
      id: 'NotoSerifTamil',
      name: 'நோட்டோ செரிஃப் (Noto Serif)',
      subtitle: 'Classic Literature',
      sampleGlyph: 'வேதம்',
      cssFamily: "'Noto Serif Tamil', serif",
      googleFontQuery: 'Noto+Serif+Tamil:wght@400;700',
      languageCode: 'tam',
    },
    {
      id: 'Catamaran',
      name: 'கட்டமரன் (Catamaran)',
      subtitle: 'Clean & Modern',
      sampleGlyph: 'சமாதானம்',
      cssFamily: "'Catamaran', sans-serif",
      googleFontQuery: 'Catamaran:wght@400;700',
      languageCode: 'tam',
    },
    {
      id: 'Kavivanar',
      name: 'கவிவாணர் (Kavivanar)',
      subtitle: 'Curved Devotional',
      sampleGlyph: 'விசுவாசம்',
      cssFamily: "'Kavivanar', cursive",
      googleFontQuery: 'Kavivanar',
      languageCode: 'tam',
    },
    {
      id: 'ArimaMadurai',
      name: 'அரிமா மதுரை (Arima)',
      subtitle: 'Graceful Calligraphy',
      sampleGlyph: 'கிருபை',
      cssFamily: "'Arima', sans-serif",
      googleFontQuery: 'Arima:wght@400;700',
      languageCode: 'tam',
    },
    {
      id: 'Coiny',
      name: 'கோய்னி (Coiny)',
      subtitle: 'Bold Rounded',
      sampleGlyph: 'ஜீவன்',
      cssFamily: "'Coiny', cursive",
      googleFontQuery: 'Coiny',
      languageCode: 'tam',
    },
  ],
  mal: [
    {
      id: 'Gayathri',
      name: 'ഗായത്രി (Gayathri)',
      subtitle: 'Contemporary Malayalam',
      sampleGlyph: 'സ്നേഹം',
      cssFamily: "'Gayathri', sans-serif",
      googleFontQuery: 'Gayathri:wght@400;700',
      languageCode: 'mal',
    },
    {
      id: 'NotoSerifMalayalam',
      name: 'നോട്ടോ സെരിഫ് (Noto Serif)',
      subtitle: 'Classic Sacred Text',
      sampleGlyph: 'സമാധാനം',
      cssFamily: "'Noto Serif Malayalam', serif",
      googleFontQuery: 'Noto+Serif+Malayalam:wght@400;700',
      languageCode: 'mal',
    },
    {
      id: 'Manjari',
      name: 'മഞ്ജരി (Manjari)',
      subtitle: 'Modern Clean',
      sampleGlyph: 'വിശ്വാസം',
      cssFamily: "'Manjari', sans-serif",
      googleFontQuery: 'Manjari:wght@400;700',
      languageCode: 'mal',
    },
    {
      id: 'Chilanka',
      name: 'ചിലങ്ക (Chilanka)',
      subtitle: 'Handwritten Script',
      sampleGlyph: 'കൃപ',
      cssFamily: "'Chilanka', cursive",
      googleFontQuery: 'Chilanka',
      languageCode: 'mal',
    },
    {
      id: 'AnekMalayalam',
      name: 'അനേക് (Anek Malayalam)',
      subtitle: 'Bold Display',
      sampleGlyph: 'ജീവൻ',
      cssFamily: "'Anek Malayalam', sans-serif",
      googleFontQuery: 'Anek+Malayalam:wght@400;700',
      languageCode: 'mal',
    },
  ],
  tel: [
    {
      id: 'Mandali',
      name: 'మండలి (Mandali)',
      subtitle: 'Clear Modern Telugu',
      sampleGlyph: 'ప్రేమ',
      cssFamily: "'Mandali', sans-serif",
      googleFontQuery: 'Mandali',
      languageCode: 'tel',
    },
    {
      id: 'NotoSerifTelugu',
      name: 'నోటో సెరిఫ్ (Noto Serif)',
      subtitle: 'Sacred Literature',
      sampleGlyph: 'శాంతి',
      cssFamily: "'Noto Serif Telugu', serif",
      googleFontQuery: 'Noto+Serif+Telugu:wght@400;700',
      languageCode: 'tel',
    },
    {
      id: 'Ramabhadra',
      name: 'రామభద్ర (Ramabhadra)',
      subtitle: 'Bold Royal',
      sampleGlyph: 'విశ్వాసం',
      cssFamily: "'Ramabhadra', sans-serif",
      googleFontQuery: 'Ramabhadra',
      languageCode: 'tel',
    },
    {
      id: 'Gidugu',
      name: 'గిడుగు (Gidugu)',
      subtitle: 'Artistic Fluid',
      sampleGlyph: 'కృప',
      cssFamily: "'Gidugu', sans-serif",
      googleFontQuery: 'Gidugu',
      languageCode: 'tel',
    },
    {
      id: 'Suranna',
      name: 'సూరన్న (Suranna)',
      subtitle: 'Classic Editorial',
      sampleGlyph: 'జీవము',
      cssFamily: "'Suranna', serif",
      googleFontQuery: 'Suranna',
      languageCode: 'tel',
    },
    {
      id: 'AnekTelugu',
      name: 'అనేక్ (Anek Telugu)',
      subtitle: 'Modern Display',
      sampleGlyph: 'వెలుగు',
      cssFamily: "'Anek Telugu', sans-serif",
      googleFontQuery: 'Anek+Telugu:wght@400;700',
      languageCode: 'tel',
    },
  ],
  hin: [
    {
      id: 'RozhaOne',
      name: 'रोज़ा वन (Rozha One)',
      subtitle: 'Dramatic Serif',
      sampleGlyph: 'प्रेम',
      cssFamily: "'Rozha One', serif",
      googleFontQuery: 'Rozha+One',
      languageCode: 'hin',
    },
    {
      id: 'NotoSerifDevanagari',
      name: 'नोटो सेरिफ़ (Noto Serif)',
      subtitle: 'Sacred Devanagari',
      sampleGlyph: 'शान्ति',
      cssFamily: "'Noto Serif Devanagari', serif",
      googleFontQuery: 'Noto+Serif+Devanagari:wght@400;700',
      languageCode: 'hin',
    },
    {
      id: 'YatraOne',
      name: 'यात्रा वन (Yatra One)',
      subtitle: 'Devotional Display',
      sampleGlyph: 'विश्वास',
      cssFamily: "'Yatra One', cursive",
      googleFontQuery: 'Yatra+One',
      languageCode: 'hin',
    },
    {
      id: 'Kalam',
      name: 'कलम (Kalam)',
      subtitle: 'Warm Handwritten',
      sampleGlyph: 'अनुग्रह',
      cssFamily: "'Kalam', cursive",
      googleFontQuery: 'Kalam:wght@400;700',
      languageCode: 'hin',
    },
    {
      id: 'Poppins',
      name: 'पॉपिन्स (Poppins)',
      subtitle: 'Clean Geometric',
      sampleGlyph: 'जीवन',
      cssFamily: "'Poppins', sans-serif",
      googleFontQuery: 'Poppins:wght@400;700',
      languageCode: 'hin',
    },
    {
      id: 'AnekDevanagari',
      name: 'अनेक (Anek Devanagari)',
      subtitle: 'Contemporary',
      sampleGlyph: 'आशा',
      cssFamily: "'Anek Devanagari', sans-serif",
      googleFontQuery: 'Anek+Devanagari:wght@400;700',
      languageCode: 'hin',
    },
  ],
  kan: [
    {
      id: 'BalooTamma2',
      name: 'ಬಾಲೂ ತಮ್ಮ ೨ (Baloo Tamma)',
      subtitle: 'Warm Rounded',
      sampleGlyph: 'ಪ್ರೀತಿ',
      cssFamily: "'Baloo Tamma 2', cursive",
      googleFontQuery: 'Baloo+Tamma+2:wght@400;700',
      languageCode: 'kan',
    },
    {
      id: 'NotoSerifKannada',
      name: 'ನೋಟೋ ಸೆರಿಫ್ (Noto Serif)',
      subtitle: 'Sacred Classic',
      sampleGlyph: 'ಶಾಂತಿ',
      cssFamily: "'Noto Serif Kannada', serif",
      googleFontQuery: 'Noto+Serif+Kannada:wght@400;700',
      languageCode: 'kan',
    },
    {
      id: 'Hubballi',
      name: 'ಹುಬ್ಬಳ್ಳಿ (Hubballi)',
      subtitle: 'Smooth Modern',
      sampleGlyph: 'ವಿಶ್ವಾಸ',
      cssFamily: "'Hubballi', sans-serif",
      googleFontQuery: 'Hubballi',
      languageCode: 'kan',
    },
    {
      id: 'AnekKannada',
      name: 'ಅನೇಕ (Anek Kannada)',
      subtitle: 'Bold Display',
      sampleGlyph: 'ಕೃಪೆ',
      cssFamily: "'Anek Kannada', sans-serif",
      googleFontQuery: 'Anek+Kannada:wght@400;700',
      languageCode: 'kan',
    },
  ],
};

export const COLOR_PALETTE: readonly ScriptureColorOption[] = [
  { hex: '#FFFFFF', name: 'Pure White' },
  { hex: '#0F172A', name: 'Obsidian Ink' },
  { hex: '#F59E0B', name: 'Radiant Gold' },
  { hex: '#FEF3C7', name: 'Warm Ivory' },
  { hex: '#1E293B', name: 'Deep Slate' },
  { hex: '#78350F', name: 'Warm Espresso' },
  { hex: '#FDE68A', name: 'Champagne' },
  { hex: '#FDA4AF', name: 'Rose Sunset' },
  { hex: '#7DD3FC', name: 'Sky Cyan' },
  { hex: '#6EE7B7', name: 'Mint Serenity' },
  { hex: '#DDD6FE', name: 'Lavender Peace' },
];

export const BACKGROUND_PRESETS: readonly BackgroundPreset[] = [
  {
    id: 'true_minimalist',
    name: 'True Minimalist',
    darkColors: ['#000000'],
    lightColors: ['#FFFFFF'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#0F172A',
    isGradient: false,
  },
  {
    id: 'editorial_paper',
    name: 'Editorial Paper',
    darkColors: ['#141414'],
    lightColors: ['#FDFBF7'],
    defaultDarkText: '#F5F5F4',
    defaultLightText: '#1C1917',
    isGradient: false,
  },
  {
    id: 'obsidian_slate',
    name: 'Obsidian Slate',
    darkColors: ['#0F172A'],
    lightColors: ['#F1F5F9'],
    defaultDarkText: '#F8FAFC',
    defaultLightText: '#0F172A',
    isGradient: false,
  },
  {
    id: 'sanctuary_warmth',
    name: 'Sanctuary Warmth',
    darkColors: ['#1C1917'],
    lightColors: ['#FFFBEB'],
    defaultDarkText: '#FEF3C7',
    defaultLightText: '#292524',
    isGradient: false,
  },
  {
    id: 'gradient_living_waters',
    name: 'Living Waters',
    darkColors: ['#082F49', '#0C4A6E', '#0369A1'],
    lightColors: ['#F0F9FF', '#E0F2FE', '#BAE6FD'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#0C4A6E',
    isGradient: true,
  },
  {
    id: 'gradient_living_hope',
    name: 'Living Hope',
    darkColors: ['#052E16', '#064E3B', '#047857'],
    lightColors: ['#F0FDF4', '#DCFCE7', '#BBF7D0'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#064E3B',
    isGradient: true,
  },
  {
    id: 'gradient_celestial_dawn',
    name: 'Celestial Dawn',
    darkColors: ['#3B0764', '#581C87', '#701A75'],
    lightColors: ['#FDF4FF', '#FAE8FF', '#E9D5FF'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#3B0764',
    isGradient: true,
  },
  {
    id: 'gradient_divine_amber',
    name: 'Divine Amber',
    darkColors: ['#451A03', '#78350F', '#9A3412'],
    lightColors: ['#FFFBEB', '#FEF3C7', '#FDE68A'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#451A03',
    isGradient: true,
  },
  {
    id: 'gradient_twilight_peace',
    name: 'Twilight Peace',
    darkColors: ['#1E1B4B', '#312E81', '#1E293B'],
    lightColors: ['#EEF2FF', '#E0E7FF', '#C7D2FE'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#1E1B4B',
    isGradient: true,
  },
  {
    id: 'gradient_royal_midnight',
    name: 'Royal Midnight',
    darkColors: ['#090D16', '#0F172A', '#1E1B4B'],
    lightColors: ['#F8FAFC', '#F1F5F9', '#E2E8F0'],
    defaultDarkText: '#FFFFFF',
    defaultLightText: '#0F172A',
    isGradient: true,
  },
];

const LEGACY_ALIASES: Record<string, string> = {
  mountain_dawn: 'gradient_celestial_dawn',
  starry_night: 'gradient_royal_midnight',
  calm_ocean: 'gradient_living_waters',
  ocean_calm: 'gradient_living_waters',
  misty_forest: 'gradient_living_hope',
  forest_sun: 'gradient_living_hope',
  golden_fields: 'gradient_divine_amber',
  desert_dunes: 'sanctuary_warmth',
  desert_dusk: 'sanctuary_warmth',
  autumn_leaves: 'gradient_divine_amber',
  night_sky: 'gradient_twilight_peace',
  gradient_radiant_gold: 'gradient_divine_amber',
  gradient_celestial_rose: 'gradient_celestial_dawn',
  gradient_emerald_sanctuary: 'gradient_living_hope',
  gradient_majestic_purple: 'gradient_celestial_dawn',
  gradient_deep_ocean: 'gradient_living_waters',
};

export function getPreset(id: string | undefined | null): BackgroundPreset {
  if (id) {
    const direct = BACKGROUND_PRESETS.find((p) => p.id === id);
    if (direct) return direct;
    const aliasId = LEGACY_ALIASES[id];
    if (aliasId) {
      const aliased = BACKGROUND_PRESETS.find((p) => p.id === aliasId);
      if (aliased) return aliased;
    }
  }
  return BACKGROUND_PRESETS[6]; // Celestial Dawn default
}

export function resolvePresetColors(
  preset: BackgroundPreset,
  isDark: boolean,
): readonly string[] {
  return isDark ? preset.darkColors : preset.lightColors;
}

export function resolvePresetCssBackground(
  preset: BackgroundPreset,
  isDark: boolean,
): string {
  const colors = resolvePresetColors(preset, isDark);
  if (colors.length === 1) return colors[0];
  return `linear-gradient(155deg, ${colors.join(', ')})`;
}

export function resolvePresetDefaultText(
  preset: BackgroundPreset,
  isDark: boolean,
): string {
  return isDark ? preset.defaultDarkText : preset.defaultLightText;
}

export function normalizeLanguageCode(lang?: string | null): string {
  switch (lang?.trim().toLowerCase()) {
    case 'ta':
    case 'tam':
    case 'tamil':
      return 'tam';
    case 'ml':
    case 'mal':
    case 'malayalam':
      return 'mal';
    case 'te':
    case 'tel':
    case 'telugu':
      return 'tel';
    case 'hi':
    case 'hin':
    case 'hindi':
      return 'hin';
    case 'kn':
    case 'kan':
    case 'kannada':
      return 'kan';
    default:
      return 'en';
  }
}

export function getLanguageForVersion(versionId: string): string {
  const id = versionId.toLowerCase();
  if (id.startsWith('ta')) return 'tam';
  if (id.startsWith('mal')) return 'mal';
  if (id.startsWith('tel')) return 'tel';
  if (id.startsWith('hin')) return 'hin';
  if (id.startsWith('kan')) return 'kan';
  return 'en';
}

export function getFontsForLanguage(
  lang?: string | null,
): readonly ScriptureFontOption[] {
  const norm = normalizeLanguageCode(lang);
  return LANGUAGE_FONTS[norm] ?? ENGLISH_FONTS;
}

export function getDefaultFontForLanguage(lang?: string | null): string {
  return getFontsForLanguage(lang)[0]?.id ?? 'Playfair';
}

export function findFontOption(
  fontId: string,
  lang?: string | null,
): ScriptureFontOption {
  const fonts = getFontsForLanguage(lang);
  return (
    fonts.find((f) => f.id === fontId) ??
    ENGLISH_FONTS.find((f) => f.id === fontId) ??
    fonts[0]
  );
}
