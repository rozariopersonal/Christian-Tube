import { Video, normalizeVideo } from './video.model';

export interface UserPlaylist {
  id: string;
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  videoCount: number;
  videos: Video[];
  createdAt: string;
  updatedAt: string;
  clientUpdatedAt: number;
}

export function normalizePlaylist(raw: unknown): UserPlaylist | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const obj = raw as Record<string, unknown>;
  const id = typeof obj['id'] === 'string' ? obj['id'].trim() : '';
  const title = typeof obj['title'] === 'string' ? obj['title'].trim() : '';
  if (!id || !title) {
    return null;
  }

  const rawVideos = Array.isArray(obj['videos'])
    ? obj['videos']
    : Array.isArray(obj['items'])
      ? obj['items']
      : [];

  const videos: Video[] = [];
  const seen = new Set<string>();
  for (const entry of rawVideos) {
    if (!entry || typeof entry !== 'object') continue;
    const rec = entry as Record<string, unknown>;
    const candidate =
      rec['video'] && typeof rec['video'] === 'object'
        ? (rec['video'] as Record<string, unknown>)
        : rec;
    const video = normalizeVideo(candidate);
    if (video.id && !seen.has(video.id)) {
      seen.add(video.id);
      videos.push(video);
    }
  }

  const rawDesc = obj['description'];
  const description =
    typeof rawDesc === 'string' && rawDesc.trim().length > 0
      ? rawDesc.trim()
      : null;

  const rawThumb = obj['thumbnailUrl'] ?? obj['thumbnail_url'];
  const thumbnailUrl =
    typeof rawThumb === 'string' && rawThumb.trim().length > 0
      ? rawThumb.trim()
      : videos[0]?.thumbnailUrl ?? null;

  const nowIso = new Date().toISOString();
  const createdAt = String(obj['createdAt'] ?? obj['created_at'] ?? nowIso);
  const updatedAt = String(obj['updatedAt'] ?? obj['updated_at'] ?? createdAt);
  const parsedUpdated = Date.parse(updatedAt);
  const rawClientUpdatedAt = Number(
    obj['clientUpdatedAt'] ?? obj['client_updated_at'],
  );
  const clientUpdatedAt =
    Number.isFinite(rawClientUpdatedAt) && rawClientUpdatedAt > 0
      ? rawClientUpdatedAt
      : Number.isFinite(parsedUpdated)
        ? parsedUpdated
        : Date.now();

  return {
    id,
    title,
    description,
    thumbnailUrl,
    videoCount: videos.length,
    videos,
    createdAt,
    updatedAt,
    clientUpdatedAt,
  };
}
