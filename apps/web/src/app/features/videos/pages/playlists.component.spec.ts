import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { vi } from 'vitest';
import { ToastService } from '../../../shared/ui/toast.service';
import { Video } from '../models/video.model';
import { PlaylistService } from '../services/playlist.service';
import { PlaylistsComponent } from './playlists.component';

function makeVideo(id = 'v1'): Video {
  return {
    id,
    title: 'Sermon 1',
    thumbnailUrl: 'https://example.com/v1.jpg',
    channelId: 'ch-1',
    channelTitle: 'Grace',
    viewCount: 10,
    publishedAt: '2026-01-01T00:00:00.000Z',
    isLive: false,
  };
}

describe('PlaylistsComponent', () => {
  let fixture: ComponentFixture<PlaylistsComponent>;
  let playlistService: PlaylistService;
  let toast: ToastService;
  let router: Router;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [PlaylistsComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();

    playlistService = TestBed.inject(PlaylistService);
    toast = TestBed.inject(ToastService);
    router = TestBed.inject(Router);
    fixture = TestBed.createComponent(PlaylistsComponent);
    fixture.detectChanges();
  });

  afterEach(() => {
    toast.clear();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('shows empty state and creates, edits, plays, and deletes playlists', () => {
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('No playlists yet');

    // Create invalid -> error toast
    fixture.componentInstance.openCreate();
    fixture.componentInstance.formTitle.set('  ');
    fixture.componentInstance.submitForm();
    expect(toast.toasts().at(-1)?.tone).toBe('error');

    // Create valid
    fixture.componentInstance.formTitle.set('Worship');
    fixture.componentInstance.formDescription.set('Morning songs');
    fixture.componentInstance.submitForm();
    fixture.detectChanges();

    expect(playlistService.playlists()).toHaveLength(1);
    const pl = playlistService.playlists()[0];
    expect(el.textContent).toContain('Worship');

    // Play All is disabled when empty
    const navSpy = vi.spyOn(router, 'navigate').mockResolvedValue(true);
    fixture.componentInstance.playAll(pl);
    expect(navSpy).not.toHaveBeenCalled();

    // Add video -> Play All navigates with ?playlist=id
    playlistService.addVideoToPlaylist(pl.id, makeVideo('v1'));
    fixture.detectChanges();
    const updatedPl = playlistService.playlistById(pl.id)!;
    fixture.componentInstance.playAll(updatedPl);
    expect(navSpy).toHaveBeenCalledWith(['/watch', 'v1'], {
      queryParams: { playlist: pl.id },
    });

    // Edit invalid & valid
    fixture.componentInstance.openEdit(updatedPl);
    fixture.componentInstance.formTitle.set('');
    fixture.componentInstance.submitForm();
    expect(toast.toasts().at(-1)?.tone).toBe('error');

    fixture.componentInstance.formTitle.set('Evening Worship');
    fixture.componentInstance.submitForm();
    fixture.detectChanges();
    expect(playlistService.playlistById(pl.id)?.title).toBe('Evening Worship');

    // Delete confirmation
    fixture.componentInstance.confirmDelete(playlistService.playlistById(pl.id)!);
    fixture.detectChanges();
    fixture.componentInstance.executeDelete();
    fixture.detectChanges();
    expect(playlistService.playlists()).toEqual([]);
  });
});
