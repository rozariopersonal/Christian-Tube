import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ReaderColumnsToggleComponent } from '../../shared/ui/reader-columns-toggle.component';
import { ReaderTypographyToggleComponent } from '../../shared/ui/reader-typography-toggle.component';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  READER_FONTS,
  READER_FONT_LANGUAGES,
  ReaderAppearanceService,
  classifySystemFontLanguage,
} from './reader-appearance.service';
import { ReleaseDataService } from '../api/release-data.service';

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

  it('clamps and persists font size via setFontSize and stepFontSize', () => {
    service.setFontSize(20);
    expect(service.fontSize()).toBe(20);
    expect(localStorage.getItem('reader_font_size')).toBe('20');

    service.stepFontSize(2);
    expect(service.fontSize()).toBe(22);

    service.stepFontSize(-5);
    expect(service.fontSize()).toBe(17);

    service.stepFontSize(-20);
    expect(service.fontSize()).toBe(13); // min clamped to 13

    service.stepFontSize(50);
    expect(service.fontSize()).toBe(28); // max clamped to 28
  });

  it('updates font and resolves activeFont with shortLabel', () => {
    expect(service.activeFont().id).toBe('system');
    expect(service.activeFont().shortLabel).toBe('System');

    service.setFont('literata');
    expect(service.fontId()).toBe('literata');
    expect(service.activeFont().shortLabel).toBe('Literata');
    expect(localStorage.getItem('reader_font_id')).toBe('literata');

    service.setFont('unknown-font');
    expect(service.activeFont().id).toBe('system');
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

  it('exposes standard fonts, line height, and letter spacing presets', () => {
    expect(READER_FONTS.map((f) => f.id)).toContain('system');
    expect(READER_FONTS.map((f) => f.id)).toContain('literata');
    expect(READER_FONTS.map((f) => f.id)).toContain('merriweather');
    expect(READER_FONTS.map((f) => f.id)).toContain('noto-tamil');

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

  it('groups reading fonts by language and supports on-demand font downloads', async () => {
    const groups = service.fontsByLanguage();
    expect(groups.map((g) => g.code)).toEqual(
      READER_FONT_LANGUAGES.map((l) => l.code),
    );

    const tamilGroup = groups.find((g) => g.code === 'ta');
    expect(tamilGroup).toBeTruthy();
    expect(tamilGroup!.fonts.map((f) => f.id)).toContain('noto-tamil');
    expect(tamilGroup!.fonts.map((f) => f.id)).toContain('mukta-malar');
    expect(tamilGroup!.onDemandCount).toBeGreaterThanOrEqual(5);

    const releases = TestBed.inject(ReleaseDataService);
    const loadSpy = vi.spyOn(releases, 'loadFont').mockResolvedValue(true);

    const ok = await service.downloadFont('mukta-malar');
    expect(ok).toBe(true);
    expect(loadSpy).toHaveBeenCalledWith('Mukta Malar', 'Mukta_Malar-Regular.ttf');
    expect(service.isFontDownloaded('mukta-malar')).toBe(true);
  });

  it('classifies system font names into language groups', () => {
    expect(classifySystemFontLanguage('Latha')).toBe('ta');
    expect(classifySystemFontLanguage('Mangal')).toBe('hi');
    expect(classifySystemFontLanguage('Gautami')).toBe('te');
    expect(classifySystemFontLanguage('Kartika')).toBe('ml');
    expect(classifySystemFontLanguage('Tunga')).toBe('kn');
    expect(classifySystemFontLanguage('Georgia')).toBe('en');
  });
});

describe('ReaderTypographyToggleComponent', () => {
  let fixture: ComponentFixture<ReaderTypographyToggleComponent>;
  let appearance: ReaderAppearanceService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [ReaderTypographyToggleComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    appearance = TestBed.inject(ReaderAppearanceService);
    fixture = TestBed.createComponent(ReaderTypographyToggleComponent);
    fixture.detectChanges();
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('renders font family trigger and allows selecting font from dropdown', () => {
    const el = fixture.nativeElement as HTMLElement;
    const fontTrigger = el.querySelector<HTMLButtonElement>('button[aria-label="Select font family"]');
    expect(fontTrigger).toBeTruthy();
    expect(fontTrigger?.textContent).toContain('System');

    fontTrigger!.click();
    fixture.detectChanges();

    const menu = el.querySelector('.font-menu-popover');
    expect(menu).toBeTruthy();

    const literataItem = el.querySelectorAll<HTMLButtonElement>('.font-menu-item')[1];
    expect(literataItem?.textContent).toContain('Literata');

    literataItem!.click();
    fixture.detectChanges();

    expect(appearance.fontId()).toBe('literata');
    expect(el.querySelector('.font-menu-popover')).toBeNull();
    expect(fontTrigger?.textContent).toContain('Literata');
  });

  it('filters fonts by language group inside the font menu popover', () => {
    const el = fixture.nativeElement as HTMLElement;
    const fontTrigger = el.querySelector<HTMLButtonElement>('button[aria-label="Select font family"]');
    fontTrigger!.click();
    fixture.detectChanges();

    const sectionsAll = el.querySelectorAll('.font-group-section');
    expect(sectionsAll.length).toBe(READER_FONT_LANGUAGES.length);

    const langChips = el.querySelectorAll<HTMLButtonElement>('.lang-chip');
    // index 0 is 'All', index 1 is 'EN', index 2 is Tamil ('தமிழ்')
    expect(langChips.length).toBe(READER_FONT_LANGUAGES.length + 1);
    langChips[2].click();
    fixture.detectChanges();

    const sectionsTamil = el.querySelectorAll('.font-group-section');
    expect(sectionsTamil.length).toBe(1);
    expect(sectionsTamil[0].textContent).toContain('Tamil');
  });

  it('steps font size up and down via steppers', () => {
    const el = fixture.nativeElement as HTMLElement;
    const initialSize = appearance.fontSize();

    const incBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Increase font size"]');
    const decBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Decrease font size"]');
    expect(incBtn).toBeTruthy();
    expect(decBtn).toBeTruthy();

    incBtn!.click();
    fixture.detectChanges();
    expect(appearance.fontSize()).toBe(initialSize + 1);

    decBtn!.click();
    fixture.detectChanges();
    expect(appearance.fontSize()).toBe(initialSize);
  });

  it('renders spacing popover and updates line and letter spacing', () => {
    const el = fixture.nativeElement as HTMLElement;
    const spacingBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Line and letter spacing"]');
    expect(spacingBtn).toBeTruthy();

    spacingBtn!.click();
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
});

describe('ReaderColumnsToggleComponent', () => {
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

  it('toggles Bible layout when showLayoutToggle is true', () => {
    fixture.componentRef.setInput('showLayoutToggle', true);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const paraBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Paragraph flow"]');
    expect(paraBtn).toBeTruthy();

    paraBtn!.click();
    fixture.detectChanges();
    expect(appearance.bibleLayout()).toBe('paragraph');

    const verseBtn = el.querySelector<HTMLButtonElement>('button[aria-label="Verse by verse"]');
    verseBtn!.click();
    fixture.detectChanges();
    expect(appearance.bibleLayout()).toBe('verses');
  });
});
