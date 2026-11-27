import { Injectable, signal } from '@angular/core';
import { Video } from '../../features/videos/models/video.model';

@Injectable({ providedIn: 'root' })
export class SaveToPlaylistModalService {
  readonly activeVideo = signal<Video | null>(null);

  open(video: Video): void {
    this.activeVideo.set(video);
  }

  close(): void {
    this.activeVideo.set(null);
  }
}
