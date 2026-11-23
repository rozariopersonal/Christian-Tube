import { AfterViewInit, Component, ElementRef, OnDestroy, ViewChild, inject, signal } from '@angular/core';
import { AuthService } from './auth.service';

@Component({
  selector: 'app-google-sign-in-button',
  standalone: true,
  template: `
    <div #button></div>
    @if (loading()) {
      <span role="status">Loading Google Sign-In…</span>
    } @else if (unavailable()) {
      <span role="alert">Google Sign-In couldn’t load. Check your connection and reload the page.</span>
    }
  `,
})
export class GoogleSignInButtonComponent implements AfterViewInit, OnDestroy {
  private readonly auth = inject(AuthService);
  @ViewChild('button', { static: true }) button!: ElementRef<HTMLElement>;
  readonly loading = signal(true);
  readonly unavailable = signal(false);
  private timer: ReturnType<typeof setInterval> | undefined;
  private attempts = 0;

  ngAfterViewInit(): void {
    if (this.renderButton()) return;
    this.timer = setInterval(() => {
      if (this.renderButton()) {
        clearInterval(this.timer);
        this.timer = undefined;
      } else if (++this.attempts >= 40) {
        clearInterval(this.timer);
        this.timer = undefined;
        this.loading.set(false);
        this.unavailable.set(true);
      }
    }, 250);
  }

  ngOnDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  private renderButton(): boolean {
    if (!this.auth.renderGoogleButton(this.button.nativeElement)) return false;
    this.loading.set(false);
    return true;
  }
}
