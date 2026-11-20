import { ComponentFixture, TestBed } from '@angular/core/testing';
import { TextSelectionPopoverComponent } from './text-selection-popover.component';
import { computeInlineToolbarAnchor } from './text-highlight.util';

describe('TextSelectionPopoverComponent (Consolidated Inline Reader Toolbar)', () => {
  let fixture: ComponentFixture<TextSelectionPopoverComponent>;
  let component: TextSelectionPopoverComponent;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [TextSelectionPopoverComponent],
    }).compileComponents();

    fixture = TestBed.createComponent(TextSelectionPopoverComponent);
    component = fixture.componentInstance;
    fixture.componentRef.setInput('anchor', {
      top: 200,
      left: 300,
      placement: 'above',
    });
  });

  it('renders highlight swatches and emits highlight/clear/define/copy/share/closed', () => {
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
    const swatches = el.querySelectorAll<HTMLButtonElement>('.swatch-btn');
    expect(swatches.length).toBe(4);
    swatches[0].click();
    expect(highlighted).toEqual(['#FEF08A']);

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
