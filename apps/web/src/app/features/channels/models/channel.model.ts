export interface Channel {
  id: string;
  title: string;
  description?: string;
  avatarUrl: string;
  bannerUrl?: string;
  subscriberCount: number;
  videoCount: number;
  isSubscribed: boolean;
  language?: string;
  hasShorts: boolean;
  isActive: boolean;
}

export interface ChannelRequest {
  id: string;
  channelName: string;
  channelUrl: string;
  status: string;
  reason?: string;
  createdAt?: string;
}

export function normalizeChannel(raw: Record<string, unknown>): Channel {
  const rawHasShorts = raw['hasShorts'] ?? raw['has_shorts'];
  return {
    id: String(raw['id'] ?? raw['channelId'] ?? raw['_id'] ?? ''),
    title: String(
      raw['title'] ?? raw['name'] ?? raw['channelTitle'] ?? 'Channel',
    ),
    description: raw['description'] ? String(raw['description']) : undefined,
    avatarUrl: String(
      raw['avatarUrl'] ??
        raw['thumbnail'] ??
        raw['avatar_url'] ??
        raw['thumbnailUrl'] ??
        '',
    ),
    bannerUrl:
      raw['bannerUrl'] ?? raw['banner_url']
        ? String(raw['bannerUrl'] ?? raw['banner_url'])
        : undefined,
    subscriberCount:
      Number(raw['subscriberCount'] ?? raw['subscriber_count'] ?? 0) || 0,
    videoCount: Number(raw['videoCount'] ?? raw['video_count'] ?? 0) || 0,
    isSubscribed: Boolean(raw['isSubscribed'] ?? raw['is_subscribed'] ?? false),
    language: raw['language'] ? String(raw['language']) : undefined,
    hasShorts:
      rawHasShorts === true ||
      rawHasShorts === 1 ||
      rawHasShorts === 'true' ||
      rawHasShorts === '1' ||
      (Number(raw['shortsCount'] ?? 0) || 0) > 0,
    isActive: raw['isActive'] !== false && raw['is_active'] !== false,
  };
}
