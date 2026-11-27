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
  notes?: string;
  submittedBy: string;
  status: string;
  createdAt?: string;
}

export interface YouTubeChannelResult {
  id: string;
  name: string;
  handle?: string;
  description?: string;
  thumbnail?: string;
  subscriberCount?: number | null;
  videoCount?: number | null;
  isExisting: boolean;
  isSynthetic?: boolean;
}

export interface ChannelActionResult {
  ok: boolean;
  error?: string;
}

export function normalizeChannelRequest(
  raw: Record<string, unknown>,
): ChannelRequest {
  const channelUrl = String(raw['channelUrl'] ?? raw['channel_url'] ?? '');
  const notes = raw['notes'] ? String(raw['notes']) : undefined;
  const rawName = raw['channelName'] ?? raw['channel_name'];
  const channelName = rawName
    ? String(rawName)
    : notes || channelUrl || 'Channel Request';
  return {
    id: String(raw['id'] ?? raw['_id'] ?? ''),
    channelName,
    channelUrl,
    notes,
    submittedBy: String(raw['submittedBy'] ?? raw['submitted_by'] ?? 'Anonymous'),
    status: String(raw['status'] ?? 'PENDING').toUpperCase(),
    createdAt: raw['createdAt'] ? String(raw['createdAt']) : undefined,
  };
}

export function normalizeYouTubeChannelResult(
  raw: Record<string, unknown>,
): YouTubeChannelResult {
  const rawSubs = raw['subscriberCount'];
  const parsedSubs =
    rawSubs === null || rawSubs === undefined || rawSubs === ''
      ? null
      : Number(rawSubs);
  const rawVids = raw['videoCount'];
  const parsedVids =
    rawVids === null || rawVids === undefined || rawVids === ''
      ? null
      : Number(rawVids);
  return {
    id: String(raw['id'] ?? ''),
    name: String(raw['name'] ?? raw['title'] ?? 'YouTube Channel'),
    handle: raw['handle'] ? String(raw['handle']) : undefined,
    description: raw['description'] ? String(raw['description']) : undefined,
    thumbnail: raw['thumbnail'] ? String(raw['thumbnail']) : undefined,
    subscriberCount:
      parsedSubs !== null && Number.isFinite(parsedSubs) ? parsedSubs : null,
    videoCount:
      parsedVids !== null && Number.isFinite(parsedVids) ? parsedVids : null,
    isExisting: Boolean(raw['isExisting']),
    isSynthetic: Boolean(raw['isSynthetic']),
  };
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
