export interface AudioTrack {
  id: string;
  title: string;
  seriesId: string;
  seriesTitle: string;
  speaker: string;
  durationSeconds: number;
  audioUrl: string;
  streamUrl?: string;
  coverUrl?: string;
  thumbnailUrl?: string;
  language?: string;
}

export interface AudioSeries {
  id: string;
  title: string;
  description: string;
  speaker: string;
  coverUrl?: string;
  trackCount: number;
  category: string;
  language: string;
  tracks: AudioTrack[];
}

export function formatDuration(totalSeconds: number): string {
  const sec = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) {
    return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  return `${m}:${String(s).padStart(2, '0')}`;
}
