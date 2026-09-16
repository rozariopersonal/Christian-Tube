import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AudioService {
  private readonly logger = new Logger(AudioService.name);
  private readonly githubBaseUrl = 'https://cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main';

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Syncs the audio catalog from the GitHub releases repo into PostgreSQL.
   */
  async syncCatalogFromGitHub() {
    this.logger.log('Starting sync of Audio Catalog from GitHub...');
    
    try {
      // 1. Fetch manifest.json to get the latest revision (optional optimization)
      // We will skip strict manifest revision checking for now to ensure it always runs when triggered.
      
      // 2. Fetch the top-level catalog.json
      const catalogRes = await fetch(`${this.githubBaseUrl}/audio/catalog.json`);
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

        // 3. Upsert the AudioSeries record
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
            trackCount: seriesData.trackCount || 0,
          },
          update: {
            title: seriesData.title,
            description: seriesData.description,
            speaker: seriesData.speaker,
            category: seriesData.category,
            language: seriesData.language,
            coverUrl: seriesData.coverUrl,
            trackCount: seriesData.trackCount || 0,
            updatedAt: new Date(),
          },
        });

        // 4. Delta Sync tracks: Only fetch the series JSON if trackCount increased
        if (!existingSeries || existingSeries.trackCount < (seriesData.trackCount || 0)) {
          this.logger.log(`Syncing new tracks for series: ${seriesData.id} (${existingSeries?.trackCount || 0} -> ${seriesData.trackCount || 0})`);
          await this.syncSeriesTracks(seriesData.id);
        }
      }

      this.logger.log('Audio catalog sync completed successfully.');
      return { success: true, count: catalog.length };
    } catch (error) {
      this.logger.error(`Error syncing audio catalog: ${error.message}`);
      throw error;
    }
  }

  private async syncSeriesTracks(seriesId: string) {
    try {
      const seriesRes = await fetch(`${this.githubBaseUrl}/audio/series/${seriesId}.json`);
      if (!seriesRes.ok) {
        this.logger.warn(`Failed to fetch series JSON for ${seriesId}`);
        return;
      }

      const seriesJson: any = await seriesRes.json();
      const tracks: any[] = seriesJson.tracks || [];

      // Upsert each track (this naturally ignores duplicates)
      for (const track of tracks) {
        await this.prisma.audioTrack.upsert({
          where: { id: track.id },
          create: {
            id: track.id,
            seriesId: seriesId,
            title: track.title,
            speaker: track.speaker,
            durationSeconds: track.durationSeconds || 0,
            audioUrl: track.audioUrl,
            ifCoverUrl: track.ifCoverUrl,
            scriptureBook: track.scriptureBook,
            scriptureChapter: track.scriptureChapter,
            scriptureVerse: track.scriptureVerse,
          },
          update: {
            title: track.title,
            speaker: track.speaker,
            durationSeconds: track.durationSeconds || 0,
            audioUrl: track.audioUrl,
            ifCoverUrl: track.ifCoverUrl,
            scriptureBook: track.scriptureBook,
            scriptureChapter: track.scriptureChapter,
            scriptureVerse: track.scriptureVerse,
            updatedAt: new Date(),
          },
        });
      }
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
      const newTracks = await this.prisma.audioTrack.findMany({
        where: { updatedAt: { gt: date } },
        include: { series: true },
      });
      // The mobile app expects a list of AudioSeries with tracks populated
      // We will group the updated tracks by their series
      const seriesMap = new Map<string, any>();
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
}
