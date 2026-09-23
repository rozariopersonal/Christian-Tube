import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** A series plus its (possibly matched) tracks, shaped for the mobile client. */
export interface SeriesSearchResult {
  id: string;
  title: string;
  description: string | null;
  speaker: string | null;
  coverUrl: string | null;
  trackCount: number;
  category: string | null;
  language: string | null;
  tracks: any[];
}

/** Raw rows from the trigram series query (SELECT column labels). */
interface RawSeriesRow {
  id: string;
  title: string;
  description: string | null;
  speaker: string | null;
  coverUrl: string | null;
  trackCount: number;
  category: string | null;
  language: string | null;
  score: number;
}

/** Raw rows from the trigram track query (series fields + track fields). */
interface RawTrackRow {
  seriesId: string;
  title: string;
  description: string | null;
  speaker: string | null;
  coverUrl: string | null;
  trackCount: number;
  category: string | null;
  language: string | null;
  trackId: string;
  trackTitle: string;
  trackSpeaker: string | null;
  trackDurationSeconds: number;
  trackAudioUrl: string;
  trackStreamUrl: string | null;
  trackFallbackUrl: string | null;
  trackCoverUrl: string | null;
  trackThumbnailUrl: string | null;
  trackYoutubeVideoId: string | null;
  trackScriptureBook: string | null;
  trackScriptureChapter: number | null;
  trackScriptureVerse: number | null;
}

@Injectable()
export class AudioService implements OnModuleInit {
  private readonly logger = new Logger(AudioService.name);
  private readonly githubBaseUrl = 'https://cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main';
  private isSyncing = false;

  /** pg_trgm similarity floor for fuzzy matches (typo tolerance). */
  private readonly fuzzyThreshold = 0.35;

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
        const latestPublished = seriesData.latestPublishedAt
          ? new Date(seriesData.latestPublishedAt)
          : null;
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
            latestPublishedAt: latestPublished,
          },
          update: {
            title: seriesData.title,
            description: seriesData.description,
            speaker: seriesData.speaker,
            category: seriesData.category,
            language: seriesData.language,
            coverUrl: seriesData.coverUrl,
            trackCount: catalogCount,
            // Only overwrite recency when the catalog actually carries it, so a
            // backfilled DB value is never clobbered by a legacy catalog entry.
            latestPublishedAt: seriesData.latestPublishedAt
              ? latestPublished
              : undefined,
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
      await this.backfillSeriesRecency(revision);
      return { success: true, count: catalog.length };
    } catch (error) {
      this.logger.error(`Error syncing audio catalog: ${error.message}`);
      throw error;
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * One-time recency backfill for legacy series. Series rows whose
   * latestPublishedAt is still NULL were created from catalog entries that
   * predate the recency field; their per-series JSON already carries track
   * publishedAt values, so we derive the latest one directly. Once populated,
   * a series is skipped on every future sync.
   */
  private async backfillSeriesRecency(revision: string = 'latest') {
    const stale = (await this.prisma.audioSeries.findMany({
      where: { latestPublishedAt: null },
      select: { id: true },
    })) ?? [];
    if (stale.length === 0) return;

    this.logger.log(`Backfilling recency for ${stale.length} series...`);
    for (const { id } of stale) {
      try {
        const res = await fetch(`${this.githubBaseUrl}/audio/series/${id}.json?rv=${revision}`);
        if (!res.ok) continue;
        const seriesJson: any = await res.json();
        const tracks: any[] = seriesJson.tracks || [];
        const latestTs = tracks.reduce<number>(
          (acc, t) =>
            t.publishedAt ? Math.max(acc, new Date(t.publishedAt).getTime()) : acc,
          0,
        );
        if (latestTs > 0) {
          await this.prisma.audioSeries.update({
            where: { id },
            data: { latestPublishedAt: new Date(latestTs) },
          });
        }
      } catch (error) {
        this.logger.warn(`Recency backfill failed for series ${id}: ${error.message}`);
      }
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
                  publishedAt: track.publishedAt
                    ? new Date(track.publishedAt)
                    : undefined,
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
      // per-series JSON so the sync endpoint never serves a stale count, and
      // refresh series recency from the same source of truth.
      const latestTs = tracks.reduce<number>(
        (acc, t) =>
          t.publishedAt ? Math.max(acc, new Date(t.publishedAt).getTime()) : acc,
        0,
      );
      await this.prisma.audioSeries.update({
        where: { id: seriesId },
        data: {
          trackCount: tracks.length,
          latestPublishedAt: latestTs > 0 ? new Date(latestTs) : undefined,
        },
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
   * Fuzzy (typo-tolerant) search over series and tracks, grouped by series.
   *
   * Uses Postgres pg_trgm `word_similarity` for fuzzy hits, with exact
   * substring (ILIKE) matches boosted above them, ranked by score. Degrades
   * to plain substring search when the trigram extension is unavailable or
   * the term is too short for trigram matching to be reliable.
   */
  async searchCatalog(query: string, limit: number = 20) {
    const clean = query.trim();
    if (!clean) return [];

    const maxLimit = Math.max(1, Math.min(limit, 50));
    if (clean.length < 3) {
      return this.substringSearchCatalog(clean, maxLimit);
    }

    try {
      return await this.trigramSearchCatalog(clean, maxLimit);
    } catch (error: any) {
      this.logger.warn(
        `Trigram fuzzy search unavailable (${error?.message}); falling back to substring search.`,
      );
      return this.substringSearchCatalog(clean, maxLimit);
    }
  }

  private async trigramSearchCatalog(clean: string, limit: number) {
    const seriesRows = await this.prisma.$queryRaw<RawSeriesRow[]>(Prisma.sql`
      SELECT
        s.id, s.title, s.description, s.speaker,
        s."coverUrl", s."trackCount", s.category, s.language,
        CASE
          WHEN s.title ILIKE '%' || ${clean} || '%' THEN 2
          WHEN s.speaker ILIKE '%' || ${clean} || '%' OR s.description ILIKE '%' || ${clean} || '%' THEN 1
          ELSE 0
        END
        + GREATEST(
          COALESCE(word_similarity(lower(${clean}), lower(COALESCE(s.title, ''))), 0),
          COALESCE(word_similarity(lower(${clean}), lower(COALESCE(s.speaker, ''))), 0),
          COALESCE(word_similarity(lower(${clean}), lower(COALESCE(s.description, ''))), 0)
        ) AS score
      FROM "AudioSeries" s
      WHERE
        s.title ILIKE '%' || ${clean} || '%'
        OR s.speaker ILIKE '%' || ${clean} || '%'
        OR s.description ILIKE '%' || ${clean} || '%'
        OR word_similarity(lower(${clean}), lower(COALESCE(s.title, ''))) > ${this.fuzzyThreshold}
        OR word_similarity(lower(${clean}), lower(COALESCE(s.speaker, ''))) > ${this.fuzzyThreshold}
        OR word_similarity(lower(${clean}), lower(COALESCE(s.description, ''))) > ${this.fuzzyThreshold}
      ORDER BY score DESC, s.title ASC
      LIMIT ${limit}
    `);

    const trackRows = await this.prisma.$queryRaw<RawTrackRow[]>(Prisma.sql`
      SELECT
        s.id AS "seriesId", s.title, s.description, s.speaker,
        s."coverUrl", s."trackCount", s.category, s.language,
        t.id AS "trackId", t.title AS "trackTitle", t.speaker AS "trackSpeaker",
        t."durationSeconds" AS "trackDurationSeconds", t."audioUrl" AS "trackAudioUrl",
        t."streamUrl" AS "trackStreamUrl", t."fallbackUrl" AS "trackFallbackUrl",
        t."ifCoverUrl" AS "trackCoverUrl", t."thumbnailUrl" AS "trackThumbnailUrl",
        t."youtubeVideoId" AS "trackYoutubeVideoId", t."scriptureBook" AS "trackScriptureBook",
        t."scriptureChapter" AS "trackScriptureChapter", t."scriptureVerse" AS "trackScriptureVerse",
        CASE WHEN t.title ILIKE '%' || ${clean} || '%' THEN 1 ELSE 0 END
          + GREATEST(
            COALESCE(word_similarity(lower(${clean}), lower(COALESCE(t.title, ''))), 0),
            COALESCE(word_similarity(lower(${clean}), lower(COALESCE(t.speaker, ''))), 0)
          ) AS score
      FROM "AudioTrack" t
      JOIN "AudioSeries" s ON s.id = t."seriesId"
      WHERE
        t.title ILIKE '%' || ${clean} || '%'
        OR t.speaker ILIKE '%' || ${clean} || '%'
        OR word_similarity(lower(${clean}), lower(COALESCE(t.title, ''))) > ${this.fuzzyThreshold}
        OR word_similarity(lower(${clean}), lower(COALESCE(t.speaker, ''))) > ${this.fuzzyThreshold}
      ORDER BY score DESC, s.title ASC
      LIMIT ${Math.min(limit * 3, 60)}
    `);

    const seriesMap = new Map<string, SeriesSearchResult>();

    for (const s of seriesRows) {
      seriesMap.set(s.id, this.projectSeries(s));
    }

    for (const r of trackRows) {
      if (!seriesMap.has(r.seriesId)) {
        seriesMap.set(r.seriesId, this.projectSeries(r));
      }
      const entry = seriesMap.get(r.seriesId)!;
      entry.tracks.push({
        id: r.trackId,
        seriesId: r.seriesId,
        seriesTitle: r.title,
        title: r.trackTitle,
        speaker: r.trackSpeaker ?? 'Zac Poonen',
        durationSeconds: r.trackDurationSeconds,
        audioUrl: r.trackAudioUrl,
        streamUrl: r.trackStreamUrl,
        fallbackUrl: r.trackFallbackUrl,
        coverUrl: r.trackCoverUrl,
        thumbnailUrl: r.trackThumbnailUrl,
        youtubeVideoId: r.trackYoutubeVideoId,
        scriptureBook: r.trackScriptureBook,
        scriptureChapter: r.trackScriptureChapter,
        scriptureVerse: r.trackScriptureVerse,
      });
    }

    return Array.from(seriesMap.values());
  }

  private projectSeries(
    row: {
      id?: string;
      seriesId?: string;
      title: string;
      description: string | null;
      speaker: string | null;
      coverUrl: string | null;
      trackCount: number;
      category: string | null;
      language: string | null;
    },
  ): SeriesSearchResult {
    return {
      id: row.id ?? row.seriesId!,
      title: row.title,
      description: row.description,
      speaker: row.speaker,
      coverUrl: row.coverUrl,
      trackCount: row.trackCount,
      category: row.category,
      language: row.language,
      tracks: [],
    };
  }

  private async substringSearchCatalog(clean: string, limit: number) {
    const tracks = await this.prisma.audioTrack.findMany({
      where: {
        OR: [
          { title: { contains: clean, mode: 'insensitive' } },
          { speaker: { contains: clean, mode: 'insensitive' } },
        ]
      },
      take: limit,
      include: { series: true },
    });

    const seriesMatches = await this.prisma.audioSeries.findMany({
      where: {
        OR: [
          { title: { contains: clean, mode: 'insensitive' } },
          { speaker: { contains: clean, mode: 'insensitive' } },
          { description: { contains: clean, mode: 'insensitive' } },
        ]
      },
      take: limit,
    });

    const seriesMap = new Map<string, SeriesSearchResult>();

    for (const s of seriesMatches) {
      seriesMap.set(s.id, { ...s, tracks: [] });
    }

    for (const track of tracks) {
      if (!seriesMap.has(track.seriesId)) {
        seriesMap.set(track.seriesId, {
          ...track.series,
          tracks: [],
        });
      }
      seriesMap.get(track.seriesId)!.tracks.push(track);
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
