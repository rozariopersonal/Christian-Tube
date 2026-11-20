import { APP_COLOR_THEMES, AppColorTheme } from '../../core/theme/theme.service';

export interface HighlightSwatch {
  index: number;
  hex: string;
  name: string;
  accentId: AppColorTheme['id'];
  shade: 0 | 1 | 2 | 3;
}

export const SHADES_PER_ACCENT = 4;
export const ACCENT_COUNT = APP_COLOR_THEMES.length; // 7
export const HIGHLIGHT_PALETTE_COUNT = SHADES_PER_ACCENT * ACCENT_COUNT; // 28

/**
 * Best 3 default swatches until usage data accumulates:
 * Warm Amber Light (4), Emerald Green Light (2), Sapphire Blue Light (0).
 */
export const DEFAULT_TOP_SWATCH_INDICES: readonly number[] = [4, 2, 0];

const SHADE_LABELS = ['Light', 'Soft', '', 'Deep'] as const;

function parseHex(hex: string): [number, number, number] {
  const clean = hex.replace('#', '');
  const n = parseInt(clean.slice(0, 6), 16);
  if (Number.isNaN(n)) return [252, 224, 177];
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function mixHex(
  rgb: [number, number, number],
  target: [number, number, number],
  t: number,
): string {
  const r = Math.min(255, Math.max(0, Math.round(rgb[0] * (1 - t) + target[0] * t)));
  const g = Math.min(255, Math.max(0, Math.round(rgb[1] * (1 - t) + target[1] * t)));
  const b = Math.min(255, Math.max(0, Math.round(rgb[2] * (1 - t) + target[2] * t)));
  return (
    '#' +
    [r, g, b].map((c) => c.toString(16).padStart(2, '0').toUpperCase()).join('')
  );
}

function shadeHex(baseHex: string, shade: 0 | 1 | 2 | 3): string {
  const rgb = parseHex(baseHex);
  switch (shade) {
    case 0:
      return mixHex(rgb, [255, 255, 255], 0.68);
    case 1:
      return mixHex(rgb, [255, 255, 255], 0.36);
    case 3:
      return mixHex(rgb, [0, 0, 0], 0.34);
    case 2:
    default:
      return baseHex.toUpperCase();
  }
}

export const HIGHLIGHT_PALETTE: readonly HighlightSwatch[] = (() => {
  const list: HighlightSwatch[] = [];
  for (let shade = 0 as 0 | 1 | 2 | 3; shade < SHADES_PER_ACCENT; shade = (shade + 1) as 0 | 1 | 2 | 3) {
    const suffix = SHADE_LABELS[shade];
    for (const theme of APP_COLOR_THEMES) {
      list.push({
        index: list.length,
        hex: shadeHex(theme.color, shade),
        name: suffix ? `${theme.name} ${suffix}` : theme.name,
        accentId: theme.id,
        shade,
      });
    }
  }
  return list;
})();

export const DEFAULT_HIGHLIGHT_HEX = HIGHLIGHT_PALETTE[DEFAULT_TOP_SWATCH_INDICES[0]].hex;

/** Returns `#111827` or `#FFFFFF` depending on relative luminance of [hex]. */
export function contrastColorFor(hex: string): string {
  const [r, g, b] = parseHex(hex).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 0.45 ? '#111827' : '#FFFFFF';
}

const LEGACY_WEB_HEX_MAP: Record<string, string> = {
  '#FEF08A': HIGHLIGHT_PALETTE[4].hex, // Yellow -> Warm Amber Light
  '#BBF7D0': HIGHLIGHT_PALETTE[2].hex, // Green -> Emerald Green Light
  '#BFDBFE': HIGHLIGHT_PALETTE[0].hex, // Blue -> Sapphire Blue Light
  '#FBCFE8': HIGHLIGHT_PALETTE[5].hex, // Pink -> Rose Pink Light
};

/** Maps legacy 4-swatch web hexes to their nearest accent-derived Light shade. */
export function migrateLegacyWebHex(hex: string): string {
  const normalized = hex.slice(0, 7).toUpperCase();
  return LEGACY_WEB_HEX_MAP[normalized] ?? hex;
}

export function findSwatchByHex(hex: string): HighlightSwatch | undefined {
  const target = migrateLegacyWebHex(hex).slice(0, 7).toUpperCase();
  return HIGHLIGHT_PALETTE.find((s) => s.hex.toUpperCase() === target);
}
