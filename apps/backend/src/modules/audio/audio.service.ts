import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AudioService implements OnModuleInit {
  private readonly logger = new Logger(AudioService.name);
  private readonly githubBaseUrl = 'https://cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main';
  private isSyncing = false;

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Self-heal: when the audio tables are empty on boot (fresh DB / new
   * deployment), pull the catalog once from the releases repository so the
   * DB-first read path always has data. Non-blocking; never throws on boot.
   */
  async onModuleInit() {
    try {
      const count = await this.prisma.audioSeries.count();
      if (count === 0) {
        this.logger.log('Audio catalog database is empty; triggering initial sync...');
        this.syncCatalogFromGitHub().catch((err) => {
          this.logger.error(`Initial audio catalog sync failed: ${err.message}`);
        });
      } else {
        this.logger.log(`Audio catalog database already populated (${count} series).`);
      }
    } catch (e: any) {
      this.logger.warn(`Could not verify audio catalog on boot: ${e.message}`);
    }
  }

  /**
   * Syncs the audio catalog from the GitHub releases repo into PostgreSQL.
   */
  async syncCatalogFromGitHub() {
    if (this.isSyncing) {
      this.logger.warn('Sync is already in progress. Skipping...');
      throw new Error('Sync already in progress');
    }
    this.isSyncing = true;
    this.logger.log('Starting sync of Audio Catalog from GitHub...');
    
    try {
      // 1. Fetch manifest.json to get the latest revision
      let revision = 'latest';
      try {
        const manifestRes = await fetch(`${this.githubBaseUrl}/manifest.json`);
        if (manifestRes.ok) {
          const manifest = await manifestRes.json();
          revision = manifest.revision || 'latest';
          this.logger.log(`Using dataset revision: ${revision}`);
        }
      } catch (err) {
        this.logger.warn(`Failed to fetch manifest.json: ${err.message}`);
      }
      
      // 2. Fetch the top-level catalog.json
      const catalogRes = await fetch(`${this.githubBaseUrl}/audio/catalog.json?rv=${revision}`);
      if (!catalogRes.ok) {
        throw new Error(`Failed to fetch catalog.json: ${catalogRes.statusText}`);
      }
      
      const catalog: any[] = await catalogRes.json();
      this.logger.log(`Fetched ${catalog.length} series from catalog.json.`);

      // Process in sequence to avoid overwhelming the database
      for (const seriesData of catalog) {
        // Find existing series in DB to compare trackCount
        const existingSeries = await this.prisma.audioSeries.findUnique({
          where: { id: seriesData.id },
        });
        const catalogCount = seriesData.trackCount || 0;

        // 3. Upsert the AudioSeries record (trackCount is refined to the real
        //    per-series JSON count inside syncSeriesTracks below)
        await this.prisma.audioSeries.upsert({
          where: { id: seriesData.id },
          create: {
            id: seriesData.id,
            title: seriesData.title,
            description: seriesData.description,
            speaker: seriesData.speaker,
            category: seriesData.category,
            language: seriesData.language,
            coverUrl: seriesData.coverUrl,
            trackCount: catalogCount,
          },
          update: {
            title: seriesData.title,
            description: seriesData.description,
            speaker: seriesData.speaker,
            category: seriesData.category,
            language: seriesData.language,
            coverUrl: seriesData.coverUrl,
            trackCount: catalogCount,
            updatedAt: new Date(),
          },
        });

        // 4. Delta Sync tracks: fetch the series JSON whenever the published
        //    trackCount differs from the stored one (grew OR shrank), or the
        //    series is new. Never skip because a count decreased.
        if (!existingSeries || existingSeries.trackCount !== catalogCount) {
          this.logger.log(`Syncing tracks for series: ${seriesData.id} (${existingSeries?.trackCount ?? 'new'} -> ${catalogCount})`);
          await this.syncSeriesTracks(seriesData.id, revision);
        }
      }

      this.logger.log('Audio catalog sync completed successfully.');
      return { success: true, count: catalog.length };
    } catch (error) {
      this.logger.error(`Error syncing audio catalog: ${error.message}`);
      throw error;
    } finally {
      this.isSyncing = false;
    }
  }

  private async syncSeriesTracks(seriesId: string, revision: string = 'latest') {
    try {
      const seriesRes = await fetch(`${this.githubBaseUrl}/audio/series/${seriesId}.json?rv=${revision}`);
      if (!seriesRes.ok) {
        this.logger.warn(`Failed to fetch series JSON for ${seriesId}`);
        return;
      }

      const seriesJson: any = await seriesRes.json();
      const tracks: any[] = seriesJson.tracks || [];

      // Batch replace tracks for the series. The delete always runs so tracks
      // removed upstream are pruned; createMany is skipped when empty so a
      // series that legitimately shrinks to zero still clears its rows.
      const deleteTracks = this.prisma.audioTrack.deleteMany({
        where: { seriesId: seriesId },
      });
      await this.prisma.$transaction([
        deleteTracks,
        ...(tracks.length > 0
          ? [
              this.prisma.audioTrack.createMany({
                data: tracks.map((track) => ({
                  id: track.id,
                  seriesId: seriesId,
                  title: track.title,
                  speaker: track.speaker,
                  durationSeconds: track.durationSeconds || 0,
                  audioUrl: track.audioUrl,
                  streamUrl: track.streamUrl,
                  fallbackUrl: track.fallbackUrl,
                  ifCoverUrl: track.ifCoverUrl,
                  thumbnailUrl: track.thumbnailUrl,
                  youtubeVideoId: track.youtubeVideoId,
                  scriptureBook: track.scriptureBook,
                  scriptureChapter: track.scriptureChapter,
                  scriptureVerse: track.scriptureVerse,
                  updatedAt: new Date(),
                })),
              }),
            ]
          : []),
      ]);

      // Keep the stored trackCount authoritative: derive it from the real
      // per-series JSON so the sync endpoint never serves a stale count.
      await this.prisma.audioSeries.update({
        where: { id: seriesId },
        data: { trackCount: tracks.length },
      });

      this.logger.log(`Replaced ${tracks.length} tracks for series ${seriesId}`);
    } catch (error) {
      this.logger.error(`Error syncing tracks for ${seriesId}: ${error.message}`);
    }
  }
  
  /**
   * Retrieves the catalog for the mobile app to sync locally.
   * If `since` is provided, only returns tracks modified after that timestamp.
   */
  async getSyncData(sinceTimestamp?: number) {
    if (sinceTimestamp) {
      const date = new Date(sinceTimestamp);
      // Include series whose row changed (title/count/metadata) even when no
      // individual track row changed, so mobile never keeps a stale trackCount.
      const changedSeries = await this.prisma.audioSeries.findMany({
        where: { updatedAt: { gt: date } },
        orderBy: { updatedAt: 'desc' },
      });
      const newTracks = await this.prisma.audioTrack.findMany({
        where: { updatedAt: { gt: date } },
        include: { series: true },
      });
      // The mobile app expects a list of AudioSeries with tracks populated
      const seriesMap = new Map<string, any>();
      for (const series of changedSeries) {
        seriesMap.set(series.id, { ...series, tracks: [] });
      }
      for (const track of newTracks) {
        if (!seriesMap.has(track.seriesId)) {
          const series = track.series;
          seriesMap.set(track.seriesId, {
            ...series,
            tracks: [],
          });
        }
        seriesMap.get(track.seriesId).tracks.push(track);
      }
      return Array.from(seriesMap.values());
    } else {
      // Full catalog
      return this.prisma.audioSeries.findMany({
        include: { tracks: true },
        orderBy: { title: 'asc' },
      });
    }
  }

  /**
   * Searches across all audio tracks and groups them by series.
   */
  async searchCatalog(query: string, limit: number = 20) {
    const searchTokens = query.trim().split(' ').map(t => t + ':*').join(' | ');

    // We search the AudioTrack table for matches using Postgres text search capabilities,
    // or just use Prisma's robust exact/contains queries since we have Prisma setup.
    // Given the hybrid requirement, we can rely on simple Prisma queries to emulate it:
    
    const tracks = await this.prisma.audioTrack.findMany({
      where: {
        OR: [
          { title: { contains: query, mode: 'insensitive' } },
          { speaker: { contains: query, mode: 'insensitive' } },
        ]
      },
      take: limit,
      include: { series: true },
    });

    // We can also search series directly
    const seriesMatches = await this.prisma.audioSeries.findMany({
      where: {
        OR: [
          { title: { contains: query, mode: 'insensitive' } },
          { speaker: { contains: query, mode: 'insensitive' } },
          { description: { contains: query, mode: 'insensitive' } },
        ]
      },
      take: limit,
    });

    // Grouping logic for the frontend response
    const seriesMap = new Map<string, any>();
    
    // Add series matches (empty tracks for now, or just the series itself)
    for (const s of seriesMatches) {
      if (!seriesMap.has(s.id)) {
        seriesMap.set(s.id, { ...s, tracks: [] });
      }
    }

    // Add track matches
    for (const track of tracks) {
      if (!seriesMap.has(track.seriesId)) {
        seriesMap.set(track.seriesId, {
          ...track.series,
          tracks: [],
        });
      }
      seriesMap.get(track.seriesId).tracks.push(track);
    }

    return Array.from(seriesMap.values());
  }

  /**
   * DB-first catalog read. Mirrors the shape of the legacy `audio/catalog.json`
   * (a list of series WITHOUT inline tracks) so mobile clients that previously
   * fetched from the releases CDN now consume the database instead.
   */
  async getCatalog() {
    return this.prisma.audioSeries.findMany({
      orderBy: { title: 'asc' },
      select: {
        id: true,
        title: true,
        description: true,
        speaker: true,
        coverUrl: true,
        trackCount: true,
        category: true,
        language: true,
      },
    });
  }

  /**
   * DB-first series read. Mirrors the shape of the legacy
   * `audio/series/{id}.json` (a series with its `tracks` inline). Mobile
   * `AudioTrack.fromJson` expects `seriesTitle` and `coverUrl` on each track,
   * which the table does not store directly — derived here from the series.
   * Returns `null` when the series does not exist.
   */
  async getSeries(id: string) {
    const series = await this.prisma.audioSeries.findUnique({
      where: { id },
      include: { tracks: true },
    });
    if (!series) return null;

    return {
      id: series.id,
      title: series.title,
      description: series.description,
      speaker: series.speaker,
      coverUrl: series.coverUrl,
      trackCount: series.trackCount,
      category: series.category,
      language: series.language,
      tracks: series.tracks.map((track) => ({
        id: track.id,
        seriesId: track.seriesId,
        seriesTitle: series.title,
        title: track.title,
        speaker: track.speaker,
        durationSeconds: track.durationSeconds,
        audioUrl: track.audioUrl,
        streamUrl: track.streamUrl,
        fallbackUrl: track.fallbackUrl,
        coverUrl: track.ifCoverUrl,
        ifCoverUrl: track.ifCoverUrl,
        thumbnailUrl: track.thumbnailUrl,
        youtubeVideoId: track.youtubeVideoId,
        scriptureBook: track.scriptureBook,
        scriptureChapter: track.scriptureChapter,
        scriptureVerse: track.scriptureVerse,
      })),
    };
  }
}
