import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ReaderColumnsToggleComponent } from '../../shared/ui/reader-columns-toggle.component';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  ReaderAppearanceService,
} from './reader-appearance.service';

describe('ReaderAppearanceService', () => {
  let service: ReaderAppearanceService;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(ReaderAppearanceService);
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('uses expected default lineHeight (1.65) and letterSpacing (0)', () => {
    expect(service.lineHeight()).toBe(1.65);
    expect(service.letterSpacing()).toBe(0);
    expect(service.formatLetterSpacing()).toBe('Normal (0em)');
  });

  it('clamps and persists lineHeight via setLineHeight and stepLineHeight', () => {
    service.setLineHeight(1.9);
    expect(service.lineHeight()).toBe(1.9);
    expect(localStorage.getItem('reader_line_height')).toBe('1.9');

    service.stepLineHeight(0.05);
    expect(service.lineHeight()).toBe(1.95);
    expect(localStorage.getItem('reader_line_height')).toBe('1.95');

    service.stepLineHeight(-0.15);
    expect(service.lineHeight()).toBe(1.8);

    service.setLineHeight(0.5);
    expect(service.lineHeight()).toBe(1.3);

    service.setLineHeight(4.0);
    expect(service.lineHeight()).toBe(2.2);

    service.setLineHeight(Number.NaN);
    expect(service.lineHeight()).toBe(2.2);
  });

  it('clamps, normalizes -0 to 0, persists, and formats letterSpacing', () => {
    service.setLetterSpacing(0.04);
    expect(service.letterSpacing()).toBe(0.04);
    expect(localStorage.getItem('reader_letter_spacing')).toBe('0.04');
    expect(service.formatLetterSpacing()).toBe('+0.04em');

    service.stepLetterSpacing(-0.06);
    expect(service.letterSpacing()).toBe(-0.02);
    expect(localStorage.getItem('reader_letter_spacing')).toBe('-0.02');
    expect(service.formatLetterSpacing()).toBe('-0.02em');

    service.setLetterSpacing(-0.001);
    expect(Object.is(service.letterSpacing(), -0)).toBe(false);
    expect(service.letterSpacing()).toBe(0);
    expect(localStorage.getItem('reader_letter_spacing')).toBe('0');
    expect(service.formatLetterSpacing()).toBe('Normal (0em)');

    service.setLetterSpacing(-0.5);
    expect(service.letterSpacing()).toBe(-0.04);

    service.setLetterSpacing(0.9);
    expect(service.letterSpacing()).toBe(0.12);

    service.setLetterSpacing(Number.NaN);
    expect(service.letterSpacing()).toBe(0.12);
  });

  it('hydrates persisted lineHeight and letterSpacing from localStorage', () => {
    TestBed.resetTestingModule();
    localStorage.setItem('reader_line_height', '1.95');
    localStorage.setItem('reader_letter_spacing', '0.05');

    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const hydrated = TestBed.inject(ReaderAppearanceService);

    expect(hydrated.lineHeight()).toBe(1.95);
    expect(hydrated.letterSpacing()).toBe(0.05);
  });

  it('exposes standard line height and letter spacing presets', () => {
    expect(LINE_HEIGHT_PRESETS.map((p) => p.label)).toEqual([
      'Tight',
      'Normal',
      'Relaxed',
    ]);
    expect(LETTER_SPACING_PRESETS.map((p) => p.label)).toEqual([
      'Tight',
      'Normal',
      'Wide',
    ]);
  });
});

describe('ReaderColumnsToggleComponent spacing toolbar', () => {
  let fixture: ComponentFixture<ReaderColumnsToggleComponent>;
  let appearance: ReaderAppearanceService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [ReaderColumnsToggleComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    appearance = TestBed.inject(ReaderAppearanceService);
    fixture = TestBed.createComponent(ReaderColumnsToggleComponent);
    fixture.detectChanges();
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('renders line and letter spacing triggers and updates appearance from popover', () => {
    const el = fixture.nativeElement as HTMLElement;
    const lineBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Line spacing"]');
    const letterBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Letter spacing"]');
    expect(lineBtn).toBeTruthy();
    expect(letterBtn).toBeTruthy();

    lineBtn!.click();
    fixture.detectChanges();

    expect(el.querySelector('.spacing-popover')).toBeTruthy();

    el.querySelector<HTMLButtonElement>('button[aria-label="Increase line spacing"]')?.click();
    fixture.detectChanges();
    expect(appearance.lineHeight()).toBe(1.7);

    el.querySelector<HTMLButtonElement>('button[aria-label="Increase letter spacing"]')?.click();
    fixture.detectChanges();
    expect(appearance.letterSpacing()).toBe(0.01);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    fixture.detectChanges();
    expect(el.querySelector('.spacing-popover')).toBeNull();
  });

  it('hides spacing controls when hideSpacing is true', () => {
    fixture.componentRef.setInput('hideSpacing', true);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('button[aria-label="Line spacing"]')).toBeNull();
    expect(el.querySelector('button[aria-label="Letter spacing"]')).toBeNull();
  });
});
