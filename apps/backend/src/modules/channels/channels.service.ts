import { Injectable, Logger, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PrismaService } from '../prisma/prisma.service';
import { YoutubeService } from '../youtube/youtube.service';

@Injectable()
export class ChannelsService {
  private readonly logger = new Logger(ChannelsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly youtubeService: YoutubeService,
  ) {}

  isAdmin(email?: string): boolean {
    if (!email) return false;
    const adminEmails = this.configService.get<string[]>('adminEmails') || [];
    return adminEmails.includes(email.trim().toLowerCase());
  }

  async findAll() {
    const channels = await this.prisma.channel.findMany({
      where: { isActive: true },
      include: {
        _count: {
          select: { videos: true },
        },
      },
      orderBy: { name: 'asc' },
    });

    return channels.map((c) => ({
      ...c,
      videoCount: c._count.videos,
    }));
  }

  async resolveChannelInfo(input: string): Promise<{
    id: string;
    name: string;
    thumbnail: string | null;
    description: string | null;
    subscriberCount: string | null;
    handle?: string | null;
  } | null> {
    let clean = input.trim();
    if (!clean) return null;

    let handle: string | null = null;
    let explicitId: string | null = null;

    if (clean.includes('youtube.com/channel/')) {
      explicitId = clean.split('youtube.com/channel/')[1].split('/')[0].split('?')[0];
    } else if (clean.includes('youtube.com/@')) {
      handle = clean.split('youtube.com/@')[1].split('/')[0].split('?')[0];
    } else if (clean.startsWith('@')) {
      handle = clean.substring(1).split('/')[0].split('?')[0];
    } else if (clean.startsWith('UC') && clean.length >= 20) {
      explicitId = clean.split('?')[0];
    } else if (!clean.startsWith('http')) {
      handle = clean;
    }

    const apiKey = this.configService.get<string>('youtubeApiKey');
    if (apiKey) {
      try {
        let endpoint = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&part=snippet,statistics`;
        if (handle) {
          endpoint += `&forHandle=${encodeURIComponent(handle)}`;
        } else if (explicitId) {
          endpoint += `&id=${encodeURIComponent(explicitId)}`;
        }
        const res = await axios.get(endpoint, { timeout: 8000 });
        if (res.data?.items?.length > 0) {
          const item = res.data.items[0];
          return {
            id: item.id,
            name: item.snippet?.title || handle || explicitId || 'Channel',
            handle: item.snippet?.customUrl || (handle ? `@${handle}` : null),
            description: item.snippet?.description || null,
            thumbnail: item.snippet?.thumbnails?.high?.url || item.snippet?.thumbnails?.medium?.url || item.snippet?.thumbnails?.default?.url || null,
            subscriberCount: item.statistics?.subscriberCount ? String(item.statistics.subscriberCount) : null,
          };
        }
      } catch (e: any) {
        this.logger.warn(`YouTube API channel resolution failed: ${e.message}`);
      }
    }

    // Scrape fallback from YouTube public page
    try {
      const targetUrl = handle
        ? `https://www.youtube.com/@${encodeURIComponent(handle)}`
        : `https://www.youtube.com/channel/${encodeURIComponent(explicitId || clean)}`;

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
        const idMatch =
          html.match(/itemprop="identifier"\s+content="(UC[a-zA-Z0-9_-]{22})"/i) ||
          html.match(/"channelId":"(UC[a-zA-Z0-9_-]{22})"/i) ||
          html.match(/https:\/\/www\.youtube\.com\/channel\/(UC[a-zA-Z0-9_-]{22})/i);

        const channelId = idMatch ? idMatch[1] : explicitId || (handle ? `@${handle}` : clean);

        const titleMatch =
          html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/i) ||
          html.match(/<title>([^<]+)<\/title>/i);
        let name = titleMatch ? titleMatch[1].replace(' - YouTube', '').trim() : handle || 'YouTube Channel';

        const thumbMatch =
          html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/i) ||
          html.match(/"avatar":{"thumbnails":\[{"url":"([^"]+)"/i);
        const thumbnail = thumbMatch ? thumbMatch[1] : null;

        const descMatch =
          html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/i) ||
          html.match(/<meta\s+name="description"\s+content="([^"]+)"/i);
        const description = descMatch ? descMatch[1] : null;

        return {
          id: channelId,
          name,
          handle: handle ? `@${handle}` : null,
          thumbnail,
          description,
          subscriberCount: null,
        };
      }
    } catch (err: any) {
      this.logger.warn(`Web fallback channel resolution error: ${err.message}`);
    }

    return {
      id: explicitId || (handle ? `@${handle}` : clean),
      name: handle || clean,
      handle: handle ? `@${handle}` : null,
      thumbnail: null,
      description: null,
      subscriberCount: null,
    };
  }

  async searchYouTube(query: string) {
    const q = (query || '').trim();
    if (!q) return [];

    const results: any[] = [];
    const seenIds = new Set<string>();

    // 1. If query is a URL or handle or UC ID, resolve directly
    if (q.startsWith('@') || q.startsWith('UC') || q.includes('youtube.com') || q.includes('youtu.be')) {
      const resolved = await this.resolveChannelInfo(q);
      if (resolved) {
        results.push(resolved);
        seenIds.add(resolved.id);
      }
    }

    // 2. Try YouTube Data API v3 if key exists
    const apiKey = this.configService.get<string>('youtubeApiKey');
    if (apiKey) {
      try {
        const searchUrl = `https://www.googleapis.com/youtube/v3/search?key=${apiKey}&q=${encodeURIComponent(q)}&type=channel&part=snippet&maxResults=15`;
        const searchRes = await axios.get(searchUrl, { timeout: 8000 });
        const items = searchRes.data?.items || [];

        if (items.length > 0) {
          const channelIds = items
            .map((it: any) => it.snippet?.channelId || it.id?.channelId)
            .filter(Boolean)
            .join(',');

          const detailsUrl = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&id=${channelIds}&part=snippet,statistics`;
          const detailsRes = await axios.get(detailsUrl, { timeout: 8000 });
          const detailMap = new Map<string, any>();
          for (const d of detailsRes.data?.items || []) {
            detailMap.set(d.id, d);
          }

          for (const it of items) {
            const id = it.snippet?.channelId || it.id?.channelId;
            if (!id || seenIds.has(id)) continue;
            seenIds.add(id);

            const detail = detailMap.get(id);
            const snippet = detail?.snippet || it.snippet;
            const stats = detail?.statistics;

            results.push({
              id,
              name: snippet?.title || 'Channel',
              handle: snippet?.customUrl || null,
              description: snippet?.description || null,
              thumbnail:
                snippet?.thumbnails?.high?.url ||
                snippet?.thumbnails?.medium?.url ||
                snippet?.thumbnails?.default?.url ||
                null,
              subscriberCount: stats?.subscriberCount ? parseInt(stats.subscriberCount, 10) : null,
              videoCount: stats?.videoCount ? parseInt(stats.videoCount, 10) : null,
            });
          }
        }
      } catch (e: any) {
        this.logger.warn(`YouTube Data API search failed: ${e.message}`);
      }
    }

    // 3. Search local database channels
    try {
      const localChannels = await this.prisma.channel.findMany({
        where: {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { id: { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
          ],
        },
        include: { _count: { select: { videos: true } } },
        take: 10,
      });

      for (const lc of localChannels) {
        if (!seenIds.has(lc.id)) {
          seenIds.add(lc.id);
          results.push({
            id: lc.id,
            name: lc.name,
            handle: null,
            description: lc.description,
            thumbnail: lc.thumbnail,
            subscriberCount: lc.subscriberCount ? parseInt(lc.subscriberCount, 10) : null,
            videoCount: lc._count.videos,
            isExisting: true,
          });
        }
      }
    } catch (_) {}

    // 4. If still empty, attempt web search resolution on YouTube
    if (results.length === 0) {
      try {
        const webSearchUrl = `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}&sp=EgIQAg%253D%253D`;
        const res = await axios.get(webSearchUrl, {
          headers: {
            'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          timeout: 8000,
        });

        const html = res.data;
        if (typeof html === 'string') {
          const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
          if (jsonMatch) {
            const data = JSON.parse(jsonMatch[1]);
            const contents =
              data?.contents?.twoColumnSearchResultsRenderer?.primaryContents?.sectionListRenderer?.contents?.[0]
                ?.itemSectionRenderer?.contents || [];

            for (const item of contents) {
              const chRenderer = item.channelRenderer;
              if (chRenderer) {
                const id = chRenderer.channelId;
                if (id && !seenIds.has(id)) {
                  seenIds.add(id);
                  const title = chRenderer.title?.simpleText || 'Channel';
                  const thumb = chRenderer.thumbnail?.thumbnails?.[0]?.url || null;
                  const desc = chRenderer.descriptionSnippet?.runs?.map((r: any) => r.text).join('') || null;
                  const subsText = chRenderer.videoCountText?.simpleText || '';

                  results.push({
                    id,
                    name: title,
                    handle: chRenderer.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl || null,
                    thumbnail: thumb ? (thumb.startsWith('//') ? `https:${thumb}` : thumb) : null,
                    description: desc,
                    subscriberCount: null,
                    videoCount: null,
                  });
                }
              }
            }
          }
        }
      } catch (err: any) {
        this.logger.warn(`Web YouTube search scraper error: ${err.message}`);
      }
    }

    // 5. If still empty, synthesize a direct channel card
    if (results.length === 0) {
      results.push({
        id: q.startsWith('@') ? q : `@${q.replaceAll(' ', '')}`,
        name: q,
        handle: q.startsWith('@') ? q : `@${q.replaceAll(' ', '')}`,
        thumbnail: null,
        description: 'Tap Add to ingest this YouTube channel directly into ChristianApp',
        subscriberCount: null,
      });
    }

    return results;
  }

  async addChannel(data: {
    channelUrl: string;
    name?: string;
    category?: string;
    language?: string;
    adminEmail?: string;
  }) {
    const rawUrl = (data.channelUrl || '').trim();
    if (!rawUrl) {
      throw new Error('Channel URL or ID is required');
    }

    const resolved = await this.resolveChannelInfo(rawUrl);
    const channelId = resolved?.id || rawUrl;
    const channelName = data.name || resolved?.name || channelId;
    const thumbnail = resolved?.thumbnail || null;
    const description = resolved?.description || null;
    const subscriberCount = resolved?.subscriberCount || null;

    const channel = await this.prisma.channel.upsert({
      where: { id: channelId },
      update: {
        name: channelName,
        category: data.category || 'General',
        language: data.language || 'English',
        thumbnail: thumbnail,
        description: description,
        subscriberCount: subscriberCount,
        isActive: true,
      },
      create: {
        id: channelId,
        name: channelName,
        category: data.category || 'General',
        language: data.language || 'English',
        thumbnail: thumbnail,
        description: description,
        subscriberCount: subscriberCount,
        isActive: true,
      },
    });

    // Trigger instant video sync (API with RSS fallback)
    this.youtubeService.syncChannelVideos(channel.id, channel.category).catch((e) => {
      this.logger.warn(`Initial sync error for added channel ${channel.id}: ${e.message}`);
    });

    return {
      status: 'success',
      message: 'Channel successfully added and video ingestion started',
      channel,
    };
  }

  async removeChannel(id: string) {
    try {
      await this.prisma.video.deleteMany({
        where: { channelId: id },
      });

      const deleted = await this.prisma.channel.delete({
        where: { id },
      });

      return {
        status: 'success',
        message: `Channel ${deleted.name} (${id}) and videos removed successfully`,
        channel: deleted,
      };
    } catch (e: any) {
      this.logger.error(`Error removing channel ${id}: ${e.message}`);
      throw e;
    }
  }

  // --- Channel Requests Workflow ---

  async listRequests() {
    return this.prisma.channelRequest.findMany({
      orderBy: { createdAt: 'desc' },
    });
  }

  async createRequest(data: { channelUrl: string; notes?: string; submittedBy?: string }) {
    return this.prisma.channelRequest.create({
      data: {
        channelUrl: data.channelUrl,
        notes: data.notes || null,
        submittedBy: data.submittedBy || 'Anonymous',
        status: 'PENDING',
      },
    });
  }

  async approveRequest(id: string, adminEmail?: string) {
    const req = await this.prisma.channelRequest.findUnique({
      where: { id },
    });

    if (!req) {
      throw new NotFoundException(`Channel request ${id} not found`);
    }

    // Add the channel to database and ingest videos
    const addResult = await this.addChannel({
      channelUrl: req.channelUrl,
      name: req.notes || undefined,
      adminEmail,
    });

    // Mark request as APPROVED
    const updatedReq = await this.prisma.channelRequest.update({
      where: { id },
      data: { status: 'APPROVED' },
    });

    return {
      status: 'success',
      message: 'Channel request approved and channel successfully added',
      request: updatedReq,
      channel: addResult.channel,
    };
  }

  async rejectRequest(id: string, reason?: string) {
    const req = await this.prisma.channelRequest.findUnique({
      where: { id },
    });

    if (!req) {
      throw new NotFoundException(`Channel request ${id} not found`);
    }

    const updatedReq = await this.prisma.channelRequest.update({
      where: { id },
      data: {
        status: 'REJECTED',
        notes: reason ? `${req.notes || ''} [Rejected: ${reason}]`.trim() : req.notes,
      },
    });

    return {
      status: 'success',
      message: 'Channel request rejected',
      request: updatedReq,
    };
  }
}
