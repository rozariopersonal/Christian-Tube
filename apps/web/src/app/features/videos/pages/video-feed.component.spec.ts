import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { ChannelService } from '../../channels/services/channel.service';
import { VideoService } from '../services/video.service';
import { VideoFeedComponent } from './video-feed.component';

describe('VideoFeedComponent', () => {
  let fixture: ComponentFixture<VideoFeedComponent>;
  let channels: ChannelService;
  let videos: VideoService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [VideoFeedComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();

    channels = TestBed.inject(ChannelService);
    videos = TestBed.inject(VideoService);
    vi.spyOn(channels, 'fetchChannels').mockResolvedValue();
    vi.spyOn(channels, 'loadSubscriptions').mockResolvedValue();
    TestBed.flushEffects();
    fixture = TestBed.createComponent(VideoFeedComponent);
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('uses All for all channels when no channels are followed', () => {
    const spy = vi.spyOn(videos, 'setFilter');
    fixture.detectChanges();

    const chips = (fixture.nativeElement as HTMLElement).querySelectorAll('.pill-chip');
    expect(Array.from(chips).map((c) => c.textContent?.trim())).toEqual([
      'thumb_up Liked',
      'All',
    ]);
    expect(spy).toHaveBeenCalledWith(
      expect.objectContaining({
        channelId: null,
        onlySubscribed: false,
      }),
    );
  });

  it('omits Followed Channels chip and filters All by followed channels when subscribed', () => {
    channels.channels.set([
      {
        id: 'ch-1',
        title: 'Grace Church',
        description: '',
        avatarUrl: '',
        bannerUrl: '',
        subscriberCount: 100,
        videoCount: 10,
        isSubscribed: true,
        hasShorts: false,
        isActive: true,
      },
    ]);
    channels.subscribedIds.set(['ch-1']);

    const spy = vi.spyOn(videos, 'setFilter');
    fixture.detectChanges();

    const labels = Array.from(
      (fixture.nativeElement as HTMLElement).querySelectorAll('.pill-chip'),
    ).map((c) => c.textContent?.trim());
    expect(labels).not.toContain('Followed Channels');
    expect(labels).toContain('thumb_up Liked');
    expect(labels.find((label) => label === 'All')).toBe('All');
    expect(labels.find((label) => label?.includes('Grace Church'))).toContain(
      'Grace Church',
    );
    expect(spy).toHaveBeenCalledWith(
      expect.objectContaining({
        channelId: null,
        onlySubscribed: true,
        subscribedIds: ['ch-1'],
      }),
    );
  });
});
