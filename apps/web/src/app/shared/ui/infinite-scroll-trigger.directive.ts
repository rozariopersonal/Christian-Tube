import {
  AfterViewInit,
  DestroyRef,
  Directive,
  ElementRef,
  effect,
  inject,
  input,
  output,
} from '@angular/core';

@Directive({
  selector: '[appInfiniteScrollTrigger]',
  standalone: true,
})
export class InfiniteScrollTriggerDirective implements AfterViewInit {
  private readonly el = inject(ElementRef<HTMLElement>);
  private readonly destroyRef = inject(DestroyRef);

  readonly disabled = input<boolean>(false);
  readonly triggered = output<void>();

  private isIntersecting = false;

  constructor() {
    effect(() => {
      const isDisabled = this.disabled();
      if (!isDisabled && this.isIntersecting) {
        queueMicrotask(() => {
          if (!this.disabled() && this.isIntersecting) {
            this.triggered.emit();
          }
        });
      }
    });
  }

  ngAfterViewInit(): void {
    if (typeof IntersectionObserver === 'undefined') return;

    const observer = new IntersectionObserver(
      (entries) => {
        this.isIntersecting = entries.some((entry) => entry.isIntersecting);
        if (this.disabled()) return;
        if (this.isIntersecting) {
          this.triggered.emit();
        }
      },
      { rootMargin: '400px 0px' },
    );

    observer.observe(this.el.nativeElement);
    this.destroyRef.onDestroy(() => observer.disconnect());
  }
}
