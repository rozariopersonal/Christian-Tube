import {
  DestroyRef,
  Directive,
  ElementRef,
  Renderer2,
  effect,
  inject,
  input,
  output,
} from '@angular/core';

interface Point {
  x: number;
  y: number;
}

const midpoint = (a: Point, b: Point): Point => ({
  x: (a.x + b.x) / 2,
  y: (a.y + b.y) / 2,
});

const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

@Directive({
  selector: '[appBookCanvasZoom]',
  standalone: true,
  host: {
    '(pointerdown)': 'pointerDown($event)',
    '(pointerup)': 'pointerEnd($event)',
    '(pointercancel)': 'pointerEnd($event)',
    '(lostpointercapture)': 'pointerEnd($event)',
    '(dblclick)': 'doubleClick($event)',
    '(gesturestart)': 'safariGestureStart($event)',
    '(gestureend)': 'safariGestureEnd($event)',
  },
})
export class BookCanvasZoomDirective {
  readonly appBookCanvasZoom = input.required<string>();
  readonly zoomContent = input.required<HTMLElement>();
  readonly turnPage = output<-1 | 1>();

  private readonly viewport = inject<ElementRef<HTMLElement>>(ElementRef).nativeElement;
  private readonly contacts = new Map<number, Point>();
  private start?: Point;
  private bounds?: DOMRect;
  private manipulated = false;
  private trackpadScale?: number;
  private scale = 1;
  private offset: Point = { x: 0, y: 0 };

  constructor() {
    const renderer = inject(Renderer2);
    const destroy = inject(DestroyRef);
    // Gesture updates change only the image layer. Keep them outside Angular's
    // template event handling so each frame doesn't dirty the reader view.
    destroy.onDestroy(
      renderer.listen(
        this.viewport,
        'pointermove',
        (event: PointerEvent) => this.pointerMove(event),
        { passive: true },
      ),
    );
    destroy.onDestroy(
      renderer.listen(this.viewport, 'wheel', (event: WheelEvent) => this.wheel(event), {
        passive: false,
      }),
    );
    destroy.onDestroy(
      renderer.listen(
        this.viewport,
        'gesturechange',
        (event: Event) => this.safariGestureChange(event),
        { passive: false },
      ),
    );
    effect(() => {
      this.appBookCanvasZoom();
      const content = this.zoomContent();
      this.contacts.clear();
      this.start = undefined;
      this.trackpadScale = undefined;
      this.scale = 1;
      this.offset = { x: 0, y: 0 };
      content.style.transform = '';
    });
    if (typeof ResizeObserver !== 'undefined') {
      const resize = new ResizeObserver(() => this.resize());
      resize.observe(this.viewport);
      destroy.onDestroy(() => resize.disconnect());
    }
  }

  pointerDown(event: PointerEvent): void {
    if (event.button !== 0 || this.isControl(event)) return;
    if (event.pointerType === 'mouse' && this.scale === 1) return;
    this.trackpadScale = undefined;
    if (this.contacts.size === 0) {
      this.bounds = this.viewport.getBoundingClientRect();
      this.start = this.localPoint(event);
      this.manipulated = this.scale > 1;
    }
    this.contacts.set(event.pointerId, this.localPoint(event));
    if (this.contacts.size > 1) this.manipulated = true;
    this.viewport.setPointerCapture(event.pointerId);
  }

  pointerMove(event: PointerEvent): void {
    const previous = this.contacts.get(event.pointerId);
    if (!previous) return;
    const pair = [...this.contacts.keys()].slice(0, 2);
    const next = this.localPoint(event);
    this.contacts.set(event.pointerId, next);
    if (pair.length === 1) {
      if (this.scale > 1) this.transform(previous, next, this.scale);
      return;
    }
    if (!pair.includes(event.pointerId)) return;

    const other = this.contacts.get(pair[0] === event.pointerId ? pair[1] : pair[0])!;
    const span = distance(previous, other);
    if (span > 0) {
      this.transform(
        midpoint(previous, other),
        midpoint(next, other),
        (this.scale * distance(next, other)) / span,
      );
    }
  }

  pointerEnd(event: PointerEvent): void {
    if (!this.contacts.delete(event.pointerId) || this.contacts.size > 0) return;
    if (event.type === 'pointerup' && !this.manipulated && this.start) {
      const end = this.localPoint(event);
      const dx = end.x - this.start.x;
      const dy = end.y - this.start.y;
      if (Math.abs(dx) >= 48 && Math.abs(dx) > Math.abs(dy)) {
        this.turnPage.emit(dx < 0 ? 1 : -1);
      }
    }
    this.start = undefined;
  }

  wheel(event: WheelEvent): void {
    if (this.contacts.size > 0 || (!event.ctrlKey && this.scale === 1)) return;
    event.preventDefault();
    if (this.trackpadScale !== undefined) return;
    this.bounds = this.viewport.getBoundingClientRect();
    const point = this.localPoint(event);
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.bounds.height : 1;
    if (event.ctrlKey) {
      this.transform(point, point, this.scale * Math.exp((-event.deltaY * unit) / 200));
    } else {
      this.transform(
        point,
        { x: point.x - event.deltaX * unit, y: point.y - event.deltaY * unit },
        this.scale,
      );
    }
  }

  doubleClick(event: MouseEvent): void {
    if (this.isControl(event) || this.contacts.size > 0) return;
    this.bounds = this.viewport.getBoundingClientRect();
    const point = this.localPoint(event);
    this.transform(point, point, this.scale > 1 ? 1 : 2);
  }

  // Safari may deliver trackpad pinch as a GestureEvent instead of a wheel event.
  safariGestureStart(event: Event): void {
    event.preventDefault();
    if (this.contacts.size > 0) return;
    this.bounds = this.viewport.getBoundingClientRect();
    this.trackpadScale = 1;
  }

  safariGestureChange(event: Event): void {
    event.preventDefault();
    if (this.trackpadScale === undefined || this.contacts.size > 0 || !this.bounds) return;
    const gesture = event as MouseEvent & { scale?: number };
    if (!gesture.scale || !Number.isFinite(gesture.scale)) return;
    const point =
      Number.isFinite(gesture.clientX) && Number.isFinite(gesture.clientY)
        ? this.localPoint(gesture)
        : { x: this.bounds.width / 2, y: this.bounds.height / 2 };
    this.transform(point, point, (this.scale * gesture.scale) / this.trackpadScale);
    this.trackpadScale = gesture.scale;
  }

  safariGestureEnd(event: Event): void {
    event.preventDefault();
    this.trackpadScale = undefined;
  }

  private resize(): void {
    const previous = this.bounds;
    const next = this.viewport.getBoundingClientRect();
    this.bounds = next;
    if (!previous || this.scale === 1) return;
    this.transform(
      { x: previous.width / 2, y: previous.height / 2 },
      { x: next.width / 2, y: next.height / 2 },
      this.scale,
    );
  }

  private localPoint(event: MouseEvent): Point {
    return {
      x: event.clientX - (this.bounds?.left ?? 0),
      y: event.clientY - (this.bounds?.top ?? 0),
    };
  }

  private transform(from: Point, to: Point, desiredScale: number): void {
    if (!this.bounds) return;
    const scale = clamp(desiredScale, 1, 4);
    const factor = scale / this.scale;
    const x = clamp(to.x - (from.x - this.offset.x) * factor, this.bounds.width * (1 - scale), 0);
    const y = clamp(to.y - (from.y - this.offset.y) * factor, this.bounds.height * (1 - scale), 0);
    this.scale = scale;
    this.offset = { x, y };
    this.zoomContent().style.transform =
      scale === 1 ? '' : `translate(${x}px, ${y}px) scale(${scale})`;
  }

  private isControl(event: MouseEvent): boolean {
    return event.target instanceof Element && !!event.target.closest('button, a, input');
  }
}
