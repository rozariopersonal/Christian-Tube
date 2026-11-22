import { Injectable } from '@angular/core';
import { WordFeedItem, WordsAppearanceState } from '../models/words-feed.model';
import {
  findFontOption,
  getLanguageForVersion,
  getPreset,
  resolvePresetColors,
} from '../models/words-theme.catalog';

@Injectable({ providedIn: 'root' })
export class WordsImageExporterService {
  async exportCard(
    item: WordFeedItem,
    appearance: WordsAppearanceState,
    isDark: boolean,
  ): Promise<'shared' | 'downloaded'> {
    const canvas = document.createElement('canvas');
    const width = 1080;
    const height = 1350;
    canvas.width = width;
    canvas.height = height;

    const ctx = canvas.getContext('2d');
    if (!ctx) {
      throw new Error('Canvas 2D context is not available');
    }

    // 1. Background (solid or gradient)
    const preset = getPreset(item.customBackgroundPreset ?? appearance.backgroundPreset);
    const colors = resolvePresetColors(preset, isDark);
    if (colors.length === 1) {
      ctx.fillStyle = colors[0];
      ctx.fillRect(0, 0, width, height);
    } else {
      const grad = ctx.createLinearGradient(0, 0, width * 0.85, height);
      colors.forEach((c, idx) => {
        grad.addColorStop(idx / Math.max(1, colors.length - 1), c);
      });
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, width, height);
    }

    // Subtle soft radial glow
    const glow = ctx.createRadialGradient(
      width * 0.5,
      height * 0.35,
      40,
      width * 0.5,
      height * 0.45,
      width * 0.75,
    );
    glow.addColorStop(0, isDark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.35)');
    glow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, width, height);

    const textColor = appearance.textColorHex || (isDark ? '#FFFFFF' : '#0F172A');
    const padX = 110;
    const maxTextWidth = width - padX * 2;
    const lang = getLanguageForVersion(appearance.activeVersionId);
    const fontOpt = findFontOption(item.customFontFamily ?? appearance.activeFontFamily, lang);
    const basePx = Math.round(48 * appearance.fontSizeScale);
    const fontStyle = appearance.isItalic ? 'italic' : 'normal';
    const fontWeight = appearance.isBold ? '700' : '400';

    // Ensure document fonts are settled if loaded
    if (typeof document !== 'undefined' && document.fonts?.ready) {
      await document.fonts.ready;
    }

    ctx.font = `${fontStyle} ${fontWeight} ${basePx}px ${fontOpt.cssFamily}`;
    ctx.fillStyle = textColor;
    ctx.textBaseline = 'top';

    const quote = item.verseText || item.theme || item.referenceLabel;
    const lines = this.wrapText(ctx, `“${quote}”`, maxTextWidth);
    const lineHeight = Math.round(basePx * 1.48);
    const blockHeight = lines.length * lineHeight;

    // 2. Decorative quote mark above text
    let startY = Math.max(190, Math.round((height - blockHeight - 180) / 2));
    ctx.save();
    ctx.globalAlpha = 0.25;
    ctx.font = `700 110px Georgia, serif`;
    ctx.fillStyle = textColor;
    ctx.textAlign = appearance.textAlign;
    const alignX =
      appearance.textAlign === 'left'
        ? padX
        : appearance.textAlign === 'right'
          ? width - padX
          : width / 2;
    ctx.fillText('“', alignX, startY - 96);
    ctx.restore();

    // 3. Verse text
    ctx.font = `${fontStyle} ${fontWeight} ${basePx}px ${fontOpt.cssFamily}`;
    ctx.fillStyle = textColor;
    ctx.textAlign = appearance.textAlign;
    lines.forEach((line, idx) => {
      ctx.fillText(line, alignX, startY + idx * lineHeight);
    });

    // 4. Reference + Version footer
    const refY = startY + blockHeight + 56;
    ctx.save();
    ctx.globalAlpha = 0.92;
    ctx.font = `700 32px 'Inter', system-ui, sans-serif`;
    ctx.fillStyle = textColor;
    ctx.textAlign = appearance.textAlign;
    const verLabel = (item.resolvedVersion || appearance.activeVersionId).toUpperCase();
    ctx.fillText(`— ${item.referenceLabel} (${verLabel})`, alignX, refY);
    ctx.restore();

    // 5. Subtle watermark
    ctx.save();
    ctx.globalAlpha = 0.45;
    ctx.font = `600 22px 'Inter', system-ui, sans-serif`;
    ctx.fillStyle = textColor;
    ctx.textAlign = 'center';
    ctx.fillText('ChristianApp · Word Feed', width / 2, height - 84);
    ctx.restore();

    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob((b) => {
        if (b) resolve(b);
        else reject(new Error('Failed to encode PNG'));
      }, 'image/png');
    });

    const filename = `word-${item.bookName.toLowerCase().replace(/\s+/g, '-')}-${item.chapter}-${item.startVerse}.png`;
    const file = new File([blob], filename, { type: 'image/png' });

    if (
      typeof navigator !== 'undefined' &&
      navigator.canShare?.({ files: [file] }) &&
      navigator.share
    ) {
      try {
        await navigator.share({
          title: item.referenceLabel,
          text: `${item.referenceLabel} (${verLabel})`,
          files: [file],
        });
        return 'shared';
      } catch {
        // Fallback to download if user cancels or share fails
      }
    }

    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    return 'downloaded';
  }

  private wrapText(
    ctx: CanvasRenderingContext2D,
    text: string,
    maxWidth: number,
  ): string[] {
    const words = text.split(/\s+/).filter(Boolean);
    const lines: string[] = [];
    let current = '';

    for (const word of words) {
      const test = current ? `${current} ${word}` : word;
      if (ctx.measureText(test).width > maxWidth && current) {
        lines.push(current);
        current = word;
      } else {
        current = test;
      }
    }
    if (current) lines.push(current);
    return lines;
  }
}
