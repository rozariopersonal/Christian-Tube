import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface ExtractedVideo {
  videoId: string;
  title: string;
  thumbnail: string;
  duration?: string;
  durationSeconds?: number;
  viewCount?: number;
  publishedAt?: Date;
  videoType: 'VIDEO' | 'SHORT';
}

export function parseIsoDurationSeconds(duration: string): number {
  if (!duration) return 0;
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 0;
  const hours = parseInt(match[1] || '0', 10);
  const minutes = parseInt(match[2] || '0', 10);
  const seconds = parseInt(match[3] || '0', 10);
  return hours * 3600 + minutes * 60 + seconds;
}

export function parseIsoDuration(duration: string): string {
  if (!duration) return '0:00';
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return '0:00';
  const hours = parseInt(match[1] || '0', 10);
  const minutes = parseInt(match[2] || '0', 10);
  const seconds = parseInt(match[3] || '0', 10);

  const secStr = seconds.toString().padStart(2, '0');
  if (hours > 0) {
    const minStr = minutes.toString().padStart(2, '0');
    return `${hours}:${minStr}:${secStr}`;
  }
  return `${minutes}:${secStr}`;
}

export function parseTextDurationToSeconds(text: string): number {
  if (!text) return 0;
  const parts = text.trim().split(':').map((p) => parseInt(p, 10));
  if (parts.length === 3) {
    return (parts[0] || 0) * 3600 + (parts[1] || 0) * 60 + (parts[2] || 0);
  }
  if (parts.length === 2) {
    return (parts[0] || 0) * 60 + (parts[1] || 0);
  }
  return 0;
}

export function parseRelativeTimeToDate(text: string): Date | null {
  if (!text || typeof text !== 'string') return null;
  const str = text
    .toLowerCase()
    .replace('streamed', '')
    .replace('premiered', '')
    .replace('live stream', '')
    .replace('scheduled', '')
    .trim();
  const now = Date.now();

  if (str === 'yesterday') {
    return new Date(now - 86400 * 1000);
  }

  const match = str.match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/i);
  if (!match) return null;

  const count = parseInt(match[1], 10);
  const unit = match[2].toLowerCase();

  switch (unit) {
    case 'second':
      return new Date(now - count * 1000);
    case 'minute':
      return new Date(now - count * 60 * 1000);
    case 'hour':
      return new Date(now - count * 3600 * 1000);
    case 'day':
      return new Date(now - count * 86400 * 1000);
    case 'week':
      return new Date(now - count * 7 * 86400 * 1000);
    case 'month':
      return new Date(now - count * 30 * 86400 * 1000);
    case 'year':
      return new Date(now - count * 365 * 86400 * 1000);
    default:
      return null;
  }
}

export function parseViewsTextToNumber(text: string): number {
  if (!text || typeof text !== 'string') return 0;
  const clean = text
    .toLowerCase()
    .replace(/views?/g, '')
    .replace(/watching/g, '')
    .trim();
  if (!clean || clean === 'no') return 0;

  if (clean.endsWith('b')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000000000);
  }
  if (clean.endsWith('m')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000000);
  }
  if (clean.endsWith('k')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000);
  }
  const digits = clean.replace(/[^0-9]/g, '');
  return digits ? parseInt(digits, 10) : 0;
}

function extractVideosFromRichContents(contents: any[]): { videos: ExtractedVideo[]; nextContinuationToken?: string } {
  const videos: ExtractedVideo[] = [];
  let nextContinuationToken: string | undefined;

  for (const item of contents) {
    if (item.continuationItemRenderer) {
      const token =
        item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token ||
        item.continuationItemRenderer?.continuationCommand?.token;
      if (token) nextContinuationToken = token;
      continue;
    }

    const content = item.richItemRenderer?.content || item;

    // 1. Modern lockupViewModel (YouTube 2024+ channel videos grid)
    if (content.lockupViewModel) {
      const vm = content.lockupViewModel;
      const videoId =
        vm.contentId ||
        vm.rendererContext?.commandContext?.onTap?.innertubeCommand?.watchEndpoint?.videoId;
      if (!videoId) continue;

      const title =
        vm.metadata?.lockupMetadataViewModel?.title?.content ||
        vm.rendererContext?.accessibilityContext?.label ||
        'Video';

      const overlays = vm.contentImage?.thumbnailViewModel?.overlays || [];
      let durationText = '';
      for (const ov of overlays) {
        const badges = ov?.thumbnailBottomOverlayViewModel?.badges;
        const badgeList = Array.isArray(badges) ? badges : [badges];
        for (const b of badgeList) {
          const t = b?.thumbnailBadgeViewModel?.text;
          if (t && typeof t === 'string' && t.includes(':')) {
            durationText = t.trim();
            break;
          }
        }
        if (durationText) break;
      }

      const durationSeconds = parseTextDurationToSeconds(durationText);
      const duration = durationText || '0:00';
      const titleLower = title.toLowerCase();
      const hasShortsTag = titleLower.includes('#short');
      const isShort =
        vm.contentType === 'LOCKUP_CONTENT_TYPE_SHORTS' ||
        (durationSeconds > 0 && durationSeconds <= 180) ||
        hasShortsTag;
      const videoType: 'VIDEO' | 'SHORT' = isShort ? 'SHORT' : 'VIDEO';

      let viewCount = 0;
      let publishedAt: Date | undefined;

      const metaRows =
        vm.metadata?.lockupMetadataViewModel?.metadata?.contentMetadataViewModel?.metadataRows ||
        vm.metadata?.lockupMetadataViewModel?.metadataRows ||
        [];

      for (const row of metaRows) {
        const parts = row?.metadataParts || [];
        for (const p of parts) {
          const t = p?.text?.content || p?.accessibilityLabel || '';
          if (!t || typeof t !== 'string') continue;
          const lower = t.toLowerCase();
          if (!viewCount && (lower.includes('view') || /^\d+(\.\d+)?[kmb]?$/i.test(lower.trim()))) {
            viewCount = parseViewsTextToNumber(t);
          }
          if (!publishedAt && (lower.includes('ago') || lower === 'yesterday')) {
            const parsed = parseRelativeTimeToDate(t);
            if (parsed) publishedAt = parsed;
          }
        }
      }

      const thumbSources = vm.contentImage?.thumbnailViewModel?.image?.sources || [];
      const thumb =
        thumbSources[thumbSources.length - 1]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration,
        durationSeconds,
        viewCount,
        publishedAt,
        videoType,
      });
      continue;
    }

    // 2. Modern shortsLockupViewModel
    if (content.shortsLockupViewModel) {
      const vm = content.shortsLockupViewModel;
      const videoId =
        vm.onTap?.innertubeCommand?.reelWatchEndpoint?.videoId ||
        (typeof vm.entityId === 'string' ? vm.entityId.replace('shorts-shelf-item-', '') : null);
      if (!videoId) continue;

      const title = vm.overlayMetadata?.primaryText?.content || 'Short';
      const thumbSources = vm.thumbnail?.sources || [];
      const thumb =
        thumbSources[thumbSources.length - 1]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      let viewCount = 0;
      const secText = vm.overlayMetadata?.secondaryText?.content || '';
      if (secText) {
        viewCount = parseViewsTextToNumber(secText);
      }

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration: '0:30',
        durationSeconds: 30,
        viewCount,
        videoType: 'SHORT',
      });
      continue;
    }

    // 3. Legacy videoRenderer / gridVideoRenderer
    const renderer = content.videoRenderer || content.gridVideoRenderer;
    if (renderer && renderer.videoId) {
      const videoId = renderer.videoId;
      const title =
        renderer.title?.runs?.map((r: any) => r.text).join('') ||
        renderer.title?.simpleText ||
        'Video';
      const durationText =
        renderer.lengthText?.simpleText ||
        renderer.thumbnailOverlays?.find((o: any) => o.thumbnailOverlayTimeStatusRenderer)
          ?.thumbnailOverlayTimeStatusRenderer?.text?.simpleText ||
        '';
      const durationSeconds = parseTextDurationToSeconds(durationText);
      const duration = durationText.trim() || '0:00';
      const titleLower = title.toLowerCase();
      const hasShortsTag = titleLower.includes('#short');
      const isShort = (durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag;
      const videoType: 'VIDEO' | 'SHORT' = isShort ? 'SHORT' : 'VIDEO';
      const thumb =
        renderer.thumbnail?.thumbnails?.slice(-1)[0]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
      const viewCountText = renderer.viewCountText?.simpleText || '';
      const viewCount = parseInt(viewCountText.replace(/[^0-9]/g, ''), 10) || 0;

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration,
        durationSeconds,
        viewCount,
        videoType,
      });
    }
  }

  return { videos, nextContinuationToken };
}

@Injectable()
export class YoutubeService {
  private readonly logger = new Logger(YoutubeService.name);
  private readonly apiKey: string;

  constructor(private readonly configService: ConfigService) {
    this.apiKey = this.configService.get<string>('youtubeApiKey') || '';
  }

  hasApiKey(): boolean {
    return !!this.apiKey;
  }

  parseIsoDuration(duration: string): string {
    return parseIsoDuration(duration);
  }

  parseIsoDurationSeconds(duration: string): number {
    return parseIsoDurationSeconds(duration);
  }

  /**
   * Fetch official channel metadata from YouTube Data API v3
   */
  async fetchChannelMetadata(channelId: string) {
    try {
      if (this.apiKey) {
        const url = `https://www.googleapis.com/youtube/v3/channels?key=${this.apiKey}&id=${encodeURIComponent(channelId)}&part=snippet,statistics`;
        const res = await axios.get(url, { timeout: 8000 });
        const item = res.data?.items?.[0];
        if (item) {
          const snippet = item.snippet;
          const stats = item.statistics;
          return {
            title: snippet?.title,
            thumbnail:
              snippet?.thumbnails?.high?.url ||
              snippet?.thumbnails?.medium?.url ||
              snippet?.thumbnails?.default?.url,
            description: snippet?.description || null,
            subscriberCount: stats?.subscriberCount ? String(stats.subscriberCount) : null,
          };
        }
      }

      // Web Scraper metadata fallback
      const targetUrl = `https://www.youtube.com/channel/${encodeURIComponent(channelId)}`;
      const res = await axios.get(targetUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const titleMatch =
          html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/i) ||
          html.match(/<title>([^<]+)<\/title>/i);
        const title = titleMatch ? titleMatch[1].replace(' - YouTube', '').trim() : undefined;

        const thumbMatch =
          html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/i) ||
          html.match(/"avatar":{"thumbnails":\[{"url":"([^"]+)"/i);
        const thumbnail = thumbMatch ? thumbMatch[1] : undefined;

        const descMatch =
          html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/i) ||
          html.match(/<meta\s+name="description"\s+content="([^"]+)"/i);
        const description = descMatch ? descMatch[1] : undefined;

        return { title, thumbnail, description, subscriberCount: null };
      }
    } catch (e: any) {
      this.logger.warn(`Could not fetch channel metadata for ${channelId}: ${e.message}`);
    }
    return null;
  }

  /**
   * Fetch 50 items from YouTube Uploads Playlist
   */
  async fetchPlaylistItems(playlistId: string, pageToken?: string) {
    const playlistUrl = `https://www.googleapis.com/youtube/v3/playlistItems?key=${this.apiKey}&playlistId=${playlistId}&part=snippet,contentDetails&maxResults=50${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const res = await axios.get(playlistUrl, { timeout: 12000 });
    return {
      items: res.data?.items || [],
      nextPageToken: res.data?.nextPageToken,
    };
  }

  /**
   * Fetch multi-ID video details (durations, statistics, snippet)
   */
  async fetchVideosDetails(videoIds: string[]): Promise<Map<string, any>> {
    const map = new Map<string, any>();
    if (!videoIds.length || !this.apiKey) return map;

    try {
      const idsStr = videoIds.join(',');
      const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${this.apiKey}&id=${idsStr}&part=snippet,contentDetails,statistics`;
      const res = await axios.get(detailsUrl, { timeout: 12000 });
      for (const it of res.data?.items || []) {
        map.set(it.id, it);
      }
    } catch (e: any) {
      this.logger.warn(`Error fetching video details: ${e.message}`);
    }
    return map;
  }

  /**
   * Scrape channel /videos tab with InnerTube continuation support
   */
  async scrapeChannelVideosTab(channelId: string, maxBatches = 10): Promise<{ videos: ExtractedVideo[] }> {
    const allVideos: ExtractedVideo[] = [];
    try {
      const videosUrl = `https://www.youtube.com/channel/${channelId}/videos`;
      const res = await axios.get(videosUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
        if (jsonMatch) {
          const data = JSON.parse(jsonMatch[1]);
          const tabs = data?.contents?.twoColumnBrowseResultsRenderer?.tabs || [];
          const videosTab = tabs.find((t: any) => t.tabRenderer?.title?.toLowerCase() === 'videos');
          const contents =
            videosTab?.tabRenderer?.content?.richGridRenderer?.contents ||
            data?.contents?.twoColumnBrowseResultsRenderer?.tabs?.[1]?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]?.itemSectionRenderer?.contents?.[0]?.gridRenderer?.items ||
            [];

          let { videos, nextContinuationToken } = extractVideosFromRichContents(contents);
          allVideos.push(...videos);

          let batch = 1;
          while (nextContinuationToken && batch < maxBatches) {
            batch++;
            try {
              const browseRes = await axios.post(
                'https://www.youtube.com/youtubei/v1/browse',
                {
                  context: { client: { clientName: 'WEB', clientVersion: '2.20240301.00.00' } },
                  continuation: nextContinuationToken,
                },
                {
                  headers: {
                    'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  timeout: 10000,
                },
              );

              const actions = browseRes.data?.onResponseReceivedActions || [];
              const continuationItems = actions[0]?.appendContinuationItemsAction?.continuationItems || [];
              const pageResult = extractVideosFromRichContents(continuationItems);
              allVideos.push(...pageResult.videos);
              nextContinuationToken = pageResult.nextContinuationToken;
            } catch (pageErr) {
              break;
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`Web scraper video pagination error for ${channelId}: ${err.message}`);
    }
    return { videos: allVideos };
  }

  /**
   * Scrape channel /shorts tab
   */
  async scrapeChannelShortsTab(channelId: string, maxBatches = 10): Promise<{ videos: ExtractedVideo[] }> {
    const allVideos: ExtractedVideo[] = [];
    try {
      const shortsUrl = `https://www.youtube.com/channel/${channelId}/shorts`;
      const res = await axios.get(shortsUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
        if (jsonMatch) {
          const data = JSON.parse(jsonMatch[1]);
          const tabs = data?.contents?.twoColumnBrowseResultsRenderer?.tabs || [];
          const shortsTab = tabs.find((t: any) => t.tabRenderer?.title?.toLowerCase() === 'shorts');
          const contents = shortsTab?.tabRenderer?.content?.richGridRenderer?.contents || [];

          let { videos, nextContinuationToken } = extractVideosFromRichContents(contents);
          allVideos.push(...videos);

          let sBatch = 1;
          while (nextContinuationToken && sBatch < maxBatches) {
            sBatch++;
            try {
              const browseRes = await axios.post(
                'https://www.youtube.com/youtubei/v1/browse',
                {
                  context: { client: { clientName: 'WEB', clientVersion: '2.20240301.00.00' } },
                  continuation: nextContinuationToken,
                },
                {
                  headers: {
                    'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  timeout: 10000,
                },
              );

              const actions = browseRes.data?.onResponseReceivedActions || [];
              const continuationItems = actions[0]?.appendContinuationItemsAction?.continuationItems || [];
              const pageResult = extractVideosFromRichContents(continuationItems);
              allVideos.push(...pageResult.videos);
              nextContinuationToken = pageResult.nextContinuationToken;
            } catch (pageErr) {
              break;
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`Web scraper shorts pagination error for ${channelId}: ${err.message}`);
    }
    return { videos: allVideos };
  }

  /**
   * Scrape Atom RSS Feed (top 15 latest uploads)
   */
  async scrapeRssFeed(channelId: string): Promise<ExtractedVideo[]> {
    const videos: ExtractedVideo[] = [];
    try {
      const feedUrl = `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`;
      const res = await axios.get(feedUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/xml,text/xml,*/*',
        },
        timeout: 10000,
      });

      const xml = res.data;
      if (xml && typeof xml === 'string') {
        const entryMatches = xml.match(/<entry>[\s\S]*?<\/entry>/g) || [];
        for (const entryXml of entryMatches) {
          const videoIdMatch = entryXml.match(/<yt:videoId>([^<]+)<\/yt:videoId>/);
          const videoId = videoIdMatch ? videoIdMatch[1].trim() : null;
          if (!videoId) continue;

          const titleMatch = entryXml.match(/<title>([\s\S]*?)<\/title>/);
          const title = titleMatch ? titleMatch[1].trim() : 'Video';

          const publishedMatch = entryXml.match(/<published>([^<]+)<\/published>/);
          const publishedAt = publishedMatch ? new Date(publishedMatch[1].trim()) : new Date();

          const thumbMatch = entryXml.match(/<media:thumbnail\s+url="([^"]+)"/);
          const thumbnail = thumbMatch
            ? thumbMatch[1]
            : `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

          const hasShortsTag = title.toLowerCase().includes('#short');
          const videoType = hasShortsTag ? 'SHORT' : 'VIDEO';

          videos.push({
            videoId,
            title,
            thumbnail,
            publishedAt,
            videoType,
          });
        }
      }
    } catch (e: any) {
      this.logger.warn(`RSS feed sync error for ${channelId}: ${e.message}`);
    }
    return videos;
  }

  /**
   * Subscribe a channel to Google WebSub Hub
   */
  async subscribeChannelToWebSub(channelId: string, mode: 'subscribe' | 'unsubscribe' = 'subscribe') {
    try {
      const apiBaseUrl = this.configService.get<string>('apiBaseUrl') || 'https://christianapp-zjdh.onrender.com';
      const callbackUrl = `${apiBaseUrl.replace(/\/$/, '')}/sync/webhook`;
      const topicUrl = `https://www.youtube.com/xml/feeds/videos.xml?channel_id=${channelId}`;

      const params = new URLSearchParams({
        'hub.callback': callbackUrl,
        'hub.mode': mode,
        'hub.topic': topicUrl,
        'hub.lease_seconds': '864000', // 10 days
      });

      const res = await axios.post('https://pubsubhubbub.appspot.com/subscribe', params.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: 10000,
      });

      this.logger.log(`Google WebSub ${mode} request submitted for channel ${channelId} (Status: ${res.status})`);
      return true;
    } catch (err: any) {
      this.logger.warn(`Google WebSub ${mode} error for channel ${channelId}: ${err.message}`);
      return false;
    }
  }
}
