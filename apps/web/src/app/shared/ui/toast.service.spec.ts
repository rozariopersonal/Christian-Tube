import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';
import { ToastHostComponent } from './toast-host.component';
import { ToastService } from './toast.service';

describe('ToastService & ToastHostComponent', () => {
  let service: ToastService;

  beforeEach(async () => {
    vi.useFakeTimers();
    await TestBed.configureTestingModule({
      imports: [ToastHostComponent],
    }).compileComponents();
    service = TestBed.inject(ToastService);
  });

  afterEach(() => {
    service.clear();
    vi.useRealTimers();
    TestBed.resetTestingModule();
  });

  it('shows toasts, auto-dismisses after duration, and supports manual dismiss/clear', () => {
    expect(service.show('   ')).toBe(-1);

    const id1 = service.show('Saved to Watch Later', 'success', 3000);
    const id2 = service.show('Failed', 'error', 0);
    expect(service.toasts()).toHaveLength(2);

    vi.advanceTimersByTime(3000);
    expect(service.toasts().map((t) => t.id)).toEqual([id2]);

    service.dismiss(id2);
    expect(service.toasts()).toEqual([]);

    service.show('A', 'info', 3000);
    service.show('B', 'info', 3000);
    service.clear();
    expect(service.toasts()).toEqual([]);
    expect(id1).toBeGreaterThan(0);
  });

  it('renders toast messages in ToastHostComponent with polite aria-live and dismiss button', () => {
    const fixture = TestBed.createComponent(ToastHostComponent);
    service.show('Added to Sermons', 'success', 0);
    service.show('Error text', 'error', 0);
    service.show('Info text', 'info', 0);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const host = el.querySelector('.toast-host');
    expect(host?.getAttribute('role')).toBe('status');
    expect(host?.getAttribute('aria-live')).toBe('polite');
    expect(el.querySelectorAll('.toast-item')).toHaveLength(3);

    const firstClose = el.querySelector('.toast-close') as HTMLButtonElement;
    firstClose.click();
    fixture.detectChanges();
    expect(el.querySelectorAll('.toast-item')).toHaveLength(2);
  });
});
