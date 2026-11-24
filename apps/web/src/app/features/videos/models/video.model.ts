export interface Video {
  id: string;
  title: string;
  description?: string;
  thumbnailUrl: string;
  channelId: string;
  channelTitle: string;
  channelAvatarUrl?: string;
  subscriberCount?: string;
  viewCount: number;
  publishedAt: string;
  duration?: string;
  streamUrl?: string;
  isLive: boolean;
  type?: string;
  category?: string;
}

export function normalizeVideo(raw: Record<string, unknown>): Video {
  const id = String(raw['id'] ?? raw['videoId'] ?? raw['_id'] ?? '');
  const defaultThumb = id
    ? `https://img.youtube.com/vi/${id}/hqdefault.jpg`
    : '';
  return {
    id,
    title: String(raw['title'] ?? ''),
    description: raw['description'] ? String(raw['description']) : undefined,
    thumbnailUrl: String(
      raw['thumbnailUrl'] ??
        raw['thumbnail_url'] ??
        raw['thumbnail'] ??
        defaultThumb,
    ),
    channelId: String(raw['channelId'] ?? raw['channel_id'] ?? ''),
    channelTitle: String(
      raw['channelTitle'] ??
        raw['channel_title'] ??
        raw['channelName'] ??
        raw['channel_name'] ??
        'Channel',
    ),
    channelAvatarUrl:
      raw['channelAvatarUrl'] ??
      raw['channel_avatar_url'] ??
      raw['channelThumbnail']
        ? String(
            raw['channelAvatarUrl'] ??
              raw['channel_avatar_url'] ??
              raw['channelThumbnail'],
          )
        : undefined,
    subscriberCount: raw['subscriberCount']
      ? String(raw['subscriberCount'])
      : undefined,
    viewCount: Number(raw['viewCount'] ?? raw['view_count'] ?? 0) || 0,
    publishedAt: String(
      raw['publishedAt'] ?? raw['published_at'] ?? new Date().toISOString(),
    ),
    duration: raw['duration'] ? String(raw['duration']) : undefined,
    streamUrl:
      raw['streamUrl'] ?? raw['stream_url']
        ? String(raw['streamUrl'] ?? raw['stream_url'])
        : undefined,
    isLive: Boolean(raw['isLive'] ?? raw['is_live'] ?? false),
    type: raw['type'] ? String(raw['type']) : undefined,
    category: raw['category'] ? String(raw['category']) : undefined,
  };
}

export function parseDurationSeconds(duration?: string): number {
  if (!duration) return 0;
  const trimmed = duration.trim();
  if (!trimmed || trimmed === '0:00') return 0;
  const parts = trimmed.split(':').map((p) => Number(p));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return 0;
  if (parts.length === 1) return Math.floor(parts[0]);
  if (parts.length === 2) return Math.floor(parts[0] * 60 + parts[1]);
  if (parts.length === 3) {
    return Math.floor(parts[0] * 3600 + parts[1] * 60 + parts[2]);
  }
  return 0;
}

export function formatViewCount(views: number): string {
  if (views >= 1_000_000) return `${(views / 1_000_000).toFixed(1)}M views`;
  if (views >= 1_000) return `${(views / 1_000).toFixed(1)}K views`;
  return `${views} views`;
}

export function formatTimeAgo(isoDate: string): string {
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return '';
  const diffSec = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
  if (diffSec < 60) return 'Just now';
  const mins = Math.floor(diffSec / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months}mo ago`;
  return `${Math.floor(months / 12)}y ago`;
}
