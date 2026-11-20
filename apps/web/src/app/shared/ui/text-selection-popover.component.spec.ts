import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HighlightUsageService } from '../services/highlight-usage.service';
import {
  HIGHLIGHT_PALETTE,
  contrastColorFor,
  migrateLegacyWebHex,
} from './highlight-palette';
import { TextSelectionPopoverComponent } from './text-selection-popover.component';
import { computeInlineToolbarAnchor } from './text-highlight.util';

describe('TextSelectionPopoverComponent (Consolidated Inline Reader Toolbar)', () => {
  let fixture: ComponentFixture<TextSelectionPopoverComponent>;
  let component: TextSelectionPopoverComponent;
  let usage: HighlightUsageService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [TextSelectionPopoverComponent],
    }).compileComponents();

    usage = TestBed.inject(HighlightUsageService);
    usage.resetForTest();
    fixture = TestBed.createComponent(TextSelectionPopoverComponent);
    component = fixture.componentInstance;
    fixture.componentRef.setInput('anchor', {
      top: 200,
      left: 300,
      placement: 'above',
    });
  });

  afterEach(() => {
    localStorage.clear();
    usage.resetForTest();
  });

  it('renders 3 default accent swatches and emits highlight/clear/define/copy/share/closed', () => {
    const highlighted: string[] = [];
    let cleared = 0;
    let defined = 0;
    let copied = 0;
    let shared = 0;
    let closed = 0;

    component.highlight.subscribe((c) => highlighted.push(c));
    component.clear.subscribe(() => cleared++);
    component.define.subscribe(() => defined++);
    component.copy.subscribe(() => copied++);
    component.share.subscribe(() => shared++);
    component.closed.subscribe(() => closed++);

    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const swatches = el.querySelectorAll<HTMLButtonElement>('.action-row .swatch-btn');
    expect(swatches.length).toBe(3);
    swatches[0].click();
    // Default top[0] is index 4 (Warm Amber Light)
    expect(highlighted).toEqual([HIGHLIGHT_PALETTE[4].hex]);

    el.querySelector<HTMLButtonElement>('button[aria-label="Clear highlight"]')?.click();
    expect(cleared).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Define"]')?.click();
    expect(defined).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Copy"]')?.click();
    expect(copied).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Share"]')?.click();
    expect(shared).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Close"]')?.click();
    expect(closed).toBe(1);
  });

  it('expands 28 accent-derived swatches (4x7) and collapses on pick', () => {
    const highlighted: string[] = [];
    component.highlight.subscribe((c) => highlighted.push(c));
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.palette-panel')).toBeNull();

    el.querySelector<HTMLButtonElement>('button[aria-label="More colours"]')?.click();
    fixture.detectChanges();

    const panel = el.querySelector('.palette-panel.top');
    expect(panel).toBeTruthy();
    expect(panel?.querySelectorAll('.palette-row').length).toBe(4);
    const allSwatches = panel!.querySelectorAll<HTMLButtonElement>('.swatch-btn');
    expect(allSwatches.length).toBe(28);

    // Pick Deep Teal (index 27)
    allSwatches[27].click();
    fixture.detectChanges();

    expect(highlighted).toEqual([HIGHLIGHT_PALETTE[27].hex]);
    expect(el.querySelector('.palette-panel')).toBeNull();
  });

  it('toggles off highlight when tapping the active swatch (including legacy hex)', () => {
    let cleared = 0;
    component.clear.subscribe(() => cleared++);
    // Legacy yellow hex maps to index 4 (Warm Amber Light)
    fixture.componentRef.setInput('activeColor', '#FEF08A');
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const swatches = el.querySelectorAll<HTMLButtonElement>('.action-row .swatch-btn');
    expect(swatches[0].classList.contains('active')).toBe(true);
    swatches[0].click();
    expect(cleared).toBe(1);
  });

  it('surfaces most-used swatches from HighlightUsageService', () => {
    usage.record(17); // Violet Purple base
    usage.record(17);
    usage.record(22); // Royal Crimson Deep
    const top = usage.topSwatches(3);
    expect(top.map((s) => s.index)).toEqual([17, 22, 4]);
  });

  it('migrates legacy 4 web hexes and computes contrast color', () => {
    expect(migrateLegacyWebHex('#FEF08A')).toBe(HIGHLIGHT_PALETTE[4].hex);
    expect(migrateLegacyWebHex('#BBF7D0')).toBe(HIGHLIGHT_PALETTE[2].hex);
    expect(migrateLegacyWebHex('#BFDBFE')).toBe(HIGHLIGHT_PALETTE[0].hex);
    expect(migrateLegacyWebHex('#FBCFE8')).toBe(HIGHLIGHT_PALETTE[5].hex);

    // Light shade gets dark text, deep shade gets white text
    expect(contrastColorFor(HIGHLIGHT_PALETTE[4].hex)).toBe('#111827');
    expect(contrastColorFor(HIGHLIGHT_PALETTE[21].hex)).toBe('#FFFFFF');
  });

  it('renders contextual Bible actions (Bookmark, Note, Compare, Cross-Refs, Study) when enabled', () => {
    fixture.componentRef.setInput('showBookmark', true);
    fixture.componentRef.setInput('isBookmarked', true);
    fixture.componentRef.setInput('showNote', true);
    fixture.componentRef.setInput('hasNote', true);
    fixture.componentRef.setInput('showCompare', true);
    fixture.componentRef.setInput('crossRefCount', 4);
    fixture.componentRef.setInput('studyTermCount', 2);

    let bookmarked = 0;
    let noted = 0;
    let compared = 0;
    let crossRefs = 0;
    let studied = 0;

    component.toggleBookmark.subscribe(() => bookmarked++);
    component.openNote.subscribe(() => noted++);
    component.compare.subscribe(() => compared++);
    component.openCrossRefs.subscribe(() => crossRefs++);
    component.openStudy.subscribe(() => studied++);

    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;

    const bmBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Bookmark"]');
    expect(bmBtn?.classList.contains('active')).toBe(true);
    bmBtn?.click();
    expect(bookmarked).toBe(1);

    const noteBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Note"]');
    expect(noteBtn?.classList.contains('active')).toBe(true);
    noteBtn?.click();
    expect(noted).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Compare"]')?.click();
    expect(compared).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Cross-Refs"]')?.click();
    expect(crossRefs).toBe(1);

    el.querySelector<HTMLButtonElement>('button[aria-label="Study"]')?.click();
    expect(studied).toBe(1);
  });

  it('computeInlineToolbarAnchor flips below when rect.top < 116', () => {
    const above = computeInlineToolbarAnchor({
      top: 260,
      bottom: 290,
      left: 200,
      width: 120,
    });
    expect(above.placement).toBe('above');

    const below = computeInlineToolbarAnchor({
      top: 70,
      bottom: 100,
      left: 200,
      width: 120,
    });
    expect(below.placement).toBe('below');
  });
});
