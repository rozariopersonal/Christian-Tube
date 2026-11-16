import {
  AfterViewInit,
  DestroyRef,
  Directive,
  ElementRef,
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

  ngAfterViewInit(): void {
    if (typeof IntersectionObserver === 'undefined') return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (this.disabled()) return;
        for (const entry of entries) {
          if (entry.isIntersecting) {
            this.triggered.emit();
            break;
          }
        }
      },
      { rootMargin: '400px 0px' },
    );

    observer.observe(this.el.nativeElement);
    this.destroyRef.onDestroy(() => observer.disconnect());
  }
}
