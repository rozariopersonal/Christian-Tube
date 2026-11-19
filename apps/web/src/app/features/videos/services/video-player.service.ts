import { Injectable, signal } from '@angular/core';
import { Video } from '../models/video.model';

@Injectable({ providedIn: 'root' })
export class VideoPlayerService {
  readonly miniVideo = signal<Video | null>(null);
  readonly startSeconds = signal<number>(0);

  openMiniPlayer(video: Video, currentSeconds = 0): void {
    this.miniVideo.set(video);
    this.startSeconds.set(Math.max(0, Math.floor(currentSeconds)));
  }

  closeMiniPlayer(): void {
    this.miniVideo.set(null);
    this.startSeconds.set(0);
  }
}
