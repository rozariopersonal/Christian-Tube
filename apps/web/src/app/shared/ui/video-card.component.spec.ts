import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { Video, parseDurationSeconds } from '../../features/videos/models/video.model';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { VideoCardComponent } from './video-card.component';

function makeVideo(overrides: Partial<Video> = {}): Video {
  return {
    id: 'vid-1',
    title: 'Walk in the Spirit',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    channelId: 'ch-1',
    channelTitle: 'Grace Church',
    viewCount: 1200,
    publishedAt: new Date(Date.now() - 86_400_000).toISOString(),
    duration: '10:00',
    isLive: false,
    ...overrides,
  };
}

describe('parseDurationSeconds', () => {
  it('parses MM:SS and HH:MM:SS formats', () => {
    expect(parseDurationSeconds('10:00')).toBe(600);
    expect(parseDurationSeconds('1:02:03')).toBe(3723);
    expect(parseDurationSeconds('0:00')).toBe(0);
    expect(parseDurationSeconds(undefined)).toBe(0);
    expect(parseDurationSeconds('invalid')).toBe(0);
  });
});

describe('VideoLibraryService & VideoCardComponent watched badge/status', () => {
  let library: VideoLibraryService;
  let fixture: ComponentFixture<VideoCardComponent>;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [VideoCardComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();

    library = TestBed.inject(VideoLibraryService);
    fixture = TestBed.createComponent(VideoCardComponent);
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('shows no watched badge or status for unwatched videos', () => {
    const video = makeVideo();
    fixture.componentRef.setInput('video', video);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.watched-badge')).toBeNull();
    expect(el.querySelector('.watched-status')).toBeNull();
    expect(el.querySelector('.progress-status')).toBeNull();
    expect(el.querySelector('.progress-track')).toBeNull();
  });

  it('shows progress bar and percentage status for in-progress videos even when durationSeconds=0 is later passed', () => {
    const video = makeVideo({ duration: '10:00' });
    library.recordProgress(video, 300, 600);
    // Simulate re-opening the video before player duration is ready
    library.recordProgress(video, 0, 0);

    expect(library.watchStatus(video.id)).toBe('in_progress');
    expect(library.progressFraction(video.id)).toBeCloseTo(0.5);

    fixture.componentRef.setInput('video', video);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.watched-badge')).toBeNull();
    expect(el.querySelector('.progress-track')).not.toBeNull();
    expect(el.querySelector('.progress-status')?.textContent?.trim()).toBe('50% watched');
  });

  it('shows watched badge and Watched status when video is completed or marked watched', () => {
    const video = makeVideo({ duration: '10:00' });
    library.markWatched(video);

    expect(library.isWatched(video.id)).toBe(true);
    expect(library.watchStatus(video.id)).toBe('watched');
    expect(library.progressFraction(video.id)).toBe(1);

    fixture.componentRef.setInput('video', video);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.watched-badge')?.textContent).toContain('Watched');
    expect(el.querySelector('.watched-status')?.textContent?.trim()).toBe('Watched');
    expect(el.querySelector('.progress-track')).not.toBeNull();
  });

  it('clears watched badge and status when marked unwatched', () => {
    const video = makeVideo({ duration: '5:00' });
    library.markWatched(video);
    fixture.componentRef.setInput('video', video);
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).querySelector('.watched-badge')).not.toBeNull();

    library.markUnwatched(video.id);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.watched-badge')).toBeNull();
    expect(el.querySelector('.watched-status')).toBeNull();
    expect(library.isWatched(video.id)).toBe(false);
  });
});
