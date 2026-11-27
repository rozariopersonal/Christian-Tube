import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';
import { vi } from 'vitest';
import { ToastService } from '../../../shared/ui/toast.service';
import { Video } from '../models/video.model';
import { PlaylistService } from '../services/playlist.service';
import { PlaylistDetailComponent } from './playlist-detail.component';

function makeVideo(id: string): Video {
  return {
    id,
    title: `Video ${id}`,
    thumbnailUrl: `https://example.com/${id}.jpg`,
    channelId: 'ch-1',
    channelTitle: 'Grace Church',
    viewCount: 50,
    publishedAt: '2026-01-01T00:00:00.000Z',
    duration: '08:15',
    isLive: false,
  };
}

describe('PlaylistDetailComponent', () => {
  let fixture: ComponentFixture<PlaylistDetailComponent>;
  let playlistService: PlaylistService;
  let toast: ToastService;
  let router: Router;
  let paramMap$: BehaviorSubject<ReturnType<typeof convertToParamMap>>;

  beforeEach(async () => {
    localStorage.clear();
    paramMap$ = new BehaviorSubject(convertToParamMap({ id: 'missing-id' }));

    await TestBed.configureTestingModule({
      imports: [PlaylistDetailComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        {
          provide: ActivatedRoute,
          useValue: {
            paramMap: paramMap$.asObservable(),
            snapshot: { paramMap: convertToParamMap({ id: 'missing-id' }) },
          },
        },
      ],
    }).compileComponents();

    playlistService = TestBed.inject(PlaylistService);
    toast = TestBed.inject(ToastService);
    router = TestBed.inject(Router);
    fixture = TestBed.createComponent(PlaylistDetailComponent);
    fixture.detectChanges();
  });

  afterEach(() => {
    toast.clear();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('shows not-found state when playlist is missing and reacts when playlist loads', () => {
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('Playlist not found');

    const pl = playlistService.createPlaylist('Study', 'Romans', makeVideo('v1'))!;
    playlistService.addVideoToPlaylist(pl.id, makeVideo('v2'));
    paramMap$.next(convertToParamMap({ id: pl.id }));
    fixture.detectChanges();

    expect(el.textContent).toContain('Study');
    expect(el.querySelectorAll('.track-row')).toHaveLength(2);
  });

  it('supports Play All, Move Up/Down, Remove, Edit, and Delete', () => {
    const pl = playlistService.createPlaylist('Sermons', 'Series', makeVideo('v1'))!;
    playlistService.addVideoToPlaylist(pl.id, makeVideo('v2'));
    paramMap$.next(convertToParamMap({ id: pl.id }));
    fixture.detectChanges();

    const navSpy = vi.spyOn(router, 'navigate').mockResolvedValue(true);

    // Play All
    fixture.componentInstance.playAll();
    expect(navSpy).toHaveBeenCalledWith(['/watch', 'v1'], {
      queryParams: { playlist: pl.id },
    });

    // Move Down (0 -> 1)
    fixture.componentInstance.move(0, 1);
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.videos.map((v) => v.id)).toEqual([
      'v2',
      'v1',
    ]);
    expect(toast.toasts().at(-1)?.message).toBe('Playlist order updated');

    // Remove video
    fixture.componentInstance.removeVideo(makeVideo('v2'));
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.videos.map((v) => v.id)).toEqual([
      'v1',
    ]);
    expect(toast.toasts().at(-1)?.message).toBe('Removed from Sermons');

    // Edit invalid & valid
    fixture.componentInstance.openEdit();
    fixture.componentInstance.editTitle.set('  ');
    fixture.componentInstance.saveEdit();
    expect(toast.toasts().at(-1)?.tone).toBe('error');

    fixture.componentInstance.editTitle.set('Renamed Sermons');
    fixture.componentInstance.saveEdit();
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.title).toBe('Renamed Sermons');

    // Delete navigates back to /playlists
    fixture.componentInstance.deletePlaylist();
    expect(playlistService.playlistById(pl.id)).toBeNull();
    expect(navSpy).toHaveBeenCalledWith(['/playlists']);
  });
});
