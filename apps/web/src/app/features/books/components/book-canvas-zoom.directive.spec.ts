import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { BookCanvasZoomDirective } from './book-canvas-zoom.directive';

@Component({
  imports: [BookCanvasZoomDirective],
  template: `
    <div
      [appBookCanvasZoom]="page().toString()"
      [zoomContent]="spread"
      (turnPage)="turns.push($event)"
    >
      <div #spread><img alt="Left scan" /><img alt="Right scan" /></div>
    </div>
  `,
})
class TestCanvas {
  readonly page = signal(1);
  readonly turns: number[] = [];
}

describe('BookCanvasZoomDirective', () => {
  it('zooms and pans the spread from the gutter, then restores touch paging at fit', () => {
    const fixture = TestBed.createComponent(TestCanvas);
    fixture.detectChanges();
    const viewport: HTMLElement = fixture.nativeElement.firstElementChild;
    const spread = viewport.firstElementChild as HTMLElement;
    viewport.setPointerCapture = () => {};
    viewport.getBoundingClientRect = () => new DOMRect(0, 0, 640, 480);

    const touch = (type: string, id: number, x: number, y: number) =>
      viewport.dispatchEvent(
        new PointerEvent(type, {
          pointerType: 'touch',
          pointerId: id,
          button: 0,
          clientX: x,
          clientY: y,
          bubbles: true,
          cancelable: true,
        }),
      );

    touch('pointerdown', 1, 290, 240);
    touch('pointerdown', 2, 350, 240);
    touch('pointermove', 1, 260, 240);
    touch('pointermove', 2, 380, 240);
    expect(spread.style.transform).toBe('translate(-320px, -240px) scale(2)');
    touch('pointerup', 1, 260, 240);
    touch('pointerup', 2, 380, 240);

    touch('pointerdown', 3, 340, 240);
    touch('pointermove', 3, 240, 200);
    touch('pointerup', 3, 240, 200);
    expect(spread.style.transform).toBe('translate(-420px, -280px) scale(2)');
    expect(fixture.componentInstance.turns).toEqual([]);

    touch('pointerdown', 4, 260, 240);
    touch('pointerdown', 5, 380, 240);
    touch('pointermove', 4, 290, 240);
    touch('pointermove', 5, 350, 240);
    touch('pointerup', 4, 290, 240);
    touch('pointerup', 5, 350, 240);
    expect(spread.style.transform).toBe('');
    expect(fixture.componentInstance.turns).toEqual([]);

    touch('pointerdown', 6, 360, 240);
    touch('pointerup', 6, 265, 240);
    expect(fixture.componentInstance.turns).toEqual([1]);

    viewport.dispatchEvent(new MouseEvent('dblclick', { clientX: 320, clientY: 240 }));
    expect(spread.style.transform).toContain('scale(2)');
    fixture.componentInstance.page.set(2);
    fixture.detectChanges();
    expect(spread.style.transform).toBe('');
  });
});
