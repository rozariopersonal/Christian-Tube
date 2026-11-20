import { TextHighlightRange } from '../../features/books/services/book-highlights.service';
import {
  ParsedScriptureRef,
  ScriptureSpanToken,
} from '../../features/books/services/scripture-ref-parser.service';

export interface HighlightedSpanToken {
  text: string;
  ref?: ParsedScriptureRef | null;
  highlightColor?: string;
}

export interface InlineToolbarAnchor {
  top: number;
  left: number;
  placement?: 'above' | 'below';
}

export interface TextSelectionAnchor extends InlineToolbarAnchor {
  scopeKey: string;
  line: number;
  start: number;
  end: number;
  text: string;
}

export function computeInlineToolbarAnchor(
  rect: Pick<DOMRect, 'top' | 'bottom' | 'left' | 'width'>,
): InlineToolbarAnchor {
  const vw = typeof window !== 'undefined' ? window.innerWidth : 1024;
  const vh = typeof window !== 'undefined' ? window.innerHeight : 768;
  const placeBelow = rect.top < 116;
  const rawTop = placeBelow ? rect.bottom + 8 : rect.top - 8;
  const top = Math.min(vh - 64, Math.max(64, rawTop));
  const halfClamp = Math.min(200, vw / 2);
  const centerX = rect.left + rect.width / 2;
  const left = Math.min(vw - halfClamp, Math.max(halfClamp, centerX));
  return {
    top,
    left,
    placement: placeBelow ? 'below' : 'above',
  };
}

export function computeElementToolbarAnchor(
  el: HTMLElement | null,
): InlineToolbarAnchor | null {
  if (!el) return null;
  const rect = el.getBoundingClientRect();
  if (rect.width === 0 && rect.height === 0) {
    return {
      top: 120,
      left: typeof window !== 'undefined' ? window.innerWidth / 2 : 300,
      placement: 'below',
    };
  }
  return computeInlineToolbarAnchor(rect);
}

export function applyHighlightRangesToTokens(
  tokens: ScriptureSpanToken[],
  ranges: TextHighlightRange[],
): HighlightedSpanToken[] {
  if (ranges.length === 0) {
    return tokens;
  }
  const out: HighlightedSpanToken[] = [];
  let offset = 0;

  for (const tok of tokens) {
    const tokStart = offset;
    const tokEnd = offset + tok.text.length;
    offset = tokEnd;
    if (!tok.text) continue;

    const overlapping = ranges.filter(
      (r) => r.end > tokStart && r.start < tokEnd,
    );
    if (overlapping.length === 0) {
      out.push(tok);
      continue;
    }

    let cursor = tokStart;
    for (const r of overlapping) {
      const segStart = Math.max(tokStart, r.start);
      const segEnd = Math.min(tokEnd, r.end);
      if (segStart > cursor) {
        out.push({
          text: tok.text.slice(cursor - tokStart, segStart - tokStart),
          ref: tok.ref,
        });
      }
      if (segEnd > segStart) {
        out.push({
          text: tok.text.slice(segStart - tokStart, segEnd - tokStart),
          ref: tok.ref,
          highlightColor: r.color,
        });
      }
      cursor = Math.max(cursor, segEnd);
    }
    if (cursor < tokEnd) {
      out.push({
        text: tok.text.slice(cursor - tokStart),
        ref: tok.ref,
      });
    }
  }

  return out;
}

export function extractLineTextSelection(): TextSelectionAnchor | null {
  const sel = window.getSelection();
  if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
  const text = sel.toString().trim();
  if (!text) return null;

  const range = sel.getRangeAt(0);
  const startEl = findLineContainer(range.startContainer);
  const endEl = findLineContainer(range.endContainer);
  if (!startEl || startEl !== endEl) return null;

  const scopeKey = startEl.dataset['hlScope'];
  const lineRaw = startEl.dataset['hlLine'];
  if (!scopeKey || lineRaw === undefined) return null;
  const line = Number(lineRaw);
  if (!Number.isFinite(line)) return null;

  const preRange = document.createRange();
  preRange.selectNodeContents(startEl);
  preRange.setEnd(range.startContainer, range.startOffset);
  const start = preRange.toString().length;
  const end = start + range.toString().length;
  if (end <= start) return null;

  const rect = range.getBoundingClientRect();
  const anchorPos = computeInlineToolbarAnchor(rect);
  return {
    scopeKey,
    line,
    start,
    end,
    text,
    ...anchorPos,
  };
}

function findLineContainer(node: Node): HTMLElement | null {
  let cur: Node | null = node;
  while (cur) {
    if (cur instanceof HTMLElement && cur.dataset['hlScope'] !== undefined) {
      return cur;
    }
    cur = cur.parentNode;
  }
  return null;
}
