import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Video } from '../../features/videos/models/video.model';
import { PlaylistService } from '../../features/videos/services/playlist.service';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { SaveToPlaylistModalComponent } from './save-to-playlist-modal.component';
import { SaveToPlaylistModalService } from './save-to-playlist-modal.service';
import { ToastService } from './toast.service';

function makeVideo(id = 'vid-1'): Video {
  return {
    id,
    title: 'Walk in the Spirit',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    channelId: 'ch-1',
    channelTitle: 'Grace Church',
    viewCount: 100,
    publishedAt: '2026-01-01T00:00:00.000Z',
    duration: '10:00',
    isLive: false,
  };
}

describe('SaveToPlaylistModalComponent', () => {
  let fixture: ComponentFixture<SaveToPlaylistModalComponent>;
  let modalService: SaveToPlaylistModalService;
  let playlistService: PlaylistService;
  let library: VideoLibraryService;
  let toast: ToastService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [SaveToPlaylistModalComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    modalService = TestBed.inject(SaveToPlaylistModalService);
    playlistService = TestBed.inject(PlaylistService);
    library = TestBed.inject(VideoLibraryService);
    toast = TestBed.inject(ToastService);
    fixture = TestBed.createComponent(SaveToPlaylistModalComponent);
  });

  afterEach(() => {
    toast.clear();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('toggles Watch Later and playlist membership with toast feedback', () => {
    const video = makeVideo('v1');
    const pl = playlistService.createPlaylist('Favorites')!;
    modalService.open(video);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const checkboxes = el.querySelectorAll<HTMLInputElement>(
      'input[type="checkbox"]',
    );
    expect(checkboxes).toHaveLength(2);

    // Toggle Watch Later ON then OFF
    checkboxes[0].dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(library.isWatchLater('v1')).toBe(true);
    expect(toast.toasts().at(-1)?.message).toBe('Saved to Watch Later');

    checkboxes[0].dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(library.isWatchLater('v1')).toBe(false);
    expect(toast.toasts().at(-1)?.message).toBe('Removed from Watch Later');

    // Toggle playlist ON then OFF
    checkboxes[1].dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.videoCount).toBe(1);
    expect(toast.toasts().at(-1)?.message).toBe('Added to Favorites');

    checkboxes[1].dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.videoCount).toBe(0);
    expect(toast.toasts().at(-1)?.message).toBe('Removed from Favorites');
  });

  it('creates a new playlist inline, auto-adds the video, and handles invalid title', () => {
    const video = makeVideo('v2');
    modalService.open(video);
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    const newBtn = el.querySelector('.new-playlist-btn') as HTMLButtonElement;
    newBtn.click();
    fixture.detectChanges();

    // Submit empty title -> error toast
    fixture.componentInstance.newTitle.set('   ');
    fixture.componentInstance.createAndAdd(video);
    expect(toast.toasts().at(-1)?.tone).toBe('error');

    // Submit valid title -> creates playlist + adds video
    fixture.componentInstance.newTitle.set('Study Series');
    fixture.componentInstance.newDescription.set('Romans');
    fixture.componentInstance.createAndAdd(video);
    fixture.detectChanges();

    expect(playlistService.playlists()).toHaveLength(1);
    expect(playlistService.playlists()[0].title).toBe('Study Series');
    expect(playlistService.playlists()[0].videos.map((v) => v.id)).toEqual(['v2']);
    expect(toast.toasts().at(-1)?.message).toBe(
      'Created "Study Series" and added video',
    );

    // Close modal
    fixture.componentInstance.close();
    fixture.detectChanges();
    expect(modalService.activeVideo()).toBeNull();
  });
});
