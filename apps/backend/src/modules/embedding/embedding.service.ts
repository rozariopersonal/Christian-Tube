import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Cron, CronExpression } from "@nestjs/schedule";
import { createHash } from "crypto";
import { PrismaService } from "../prisma/prisma.service";

interface CachedEmbedding {
  vector: number[];
  at: number;
}

export type EmbeddingProvider = 'self-hosted' | 'huggingface';

@Injectable()
export class EmbeddingService {
  private readonly logger = new Logger(EmbeddingService.name);

  private readonly enabled: boolean;
  private readonly provider: EmbeddingProvider;
  private readonly serviceUrl: string | null;
  private readonly authToken: string;
  private readonly model: string;
  private readonly dim: number;
  private readonly version: number;
  private readonly queryPrefix = "query: ";
  private readonly passagePrefix = "passage: ";

  private readonly cache = new Map<string, CachedEmbedding>();
  private readonly cacheTtlMs = 5 * 60 * 1000;
  private readonly timeoutMs: number;
  private readonly maxCacheEntries = 256;

  private lastError: string | null = null;
  private lastSuccessAt: number | null = null;
  private lastAttemptAt: number | null = null;
  private lastCallMs: number | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.enabled =
      this.configService.get<boolean>("embedding.enabled") ?? false;
    this.provider =
      this.configService.get<EmbeddingProvider>("embedding.provider") ||
      "self-hosted";
    this.serviceUrl =
      this.configService.get<string>("embedding.serviceUrl") || null;
    this.authToken =
      this.configService.get<string>("embedding.authToken") || "";
    this.model =
      this.configService.get<string>("embedding.model") ||
      "intfloat/multilingual-e5-small";
    this.dim = this.configService.get<number>("embedding.dim") || 384;
    this.version = this.configService.get<number>("embedding.version") || 1;
    this.timeoutMs =
      this.configService.get<number>("embedding.timeoutMs") ??
      (this.provider === "huggingface" ? 8000 : 1500);
  }

  get modelName(): string {
    return this.model;
  }

  get modelVersion(): number {
    return this.version;
  }

  get embeddingDim(): number {
    return this.dim;
  }

  /**
   * Live diagnostics for the query-embedding upstream. Zero secrets.
   */
  getStatus() {
    return {
      enabled: this.enabled,
      isEnabled: this.isEnabled,
      provider: this.provider,
      serviceUrl: this.serviceUrl,
      authTokenSet: this.authToken.length > 0,
      model: this.model,
      dim: this.dim,
      version: this.version,
      timeoutMs: this.timeoutMs,
      cacheSize: this.cache.size,
      lastError: this.lastError,
      lastAttemptAt: this.lastAttemptAt
        ? new Date(this.lastAttemptAt).toISOString()
        : null,
      lastSuccessAt: this.lastSuccessAt
        ? new Date(this.lastSuccessAt).toISOString()
        : null,
      lastCallMs: this.lastCallMs,
    };
  }

  get isEnabled(): boolean {
    return this.enabled && !!this.serviceUrl;
  }

  private get embedUrl(): string {
    if (this.provider === "huggingface") {
      return `${this.serviceUrl}/models/${this.model}/pipeline/feature-extraction`;
    }
    return `${this.serviceUrl}/embed`;
  }

  private embedBody(text: string): unknown {
    if (this.provider === "huggingface") {
      return { inputs: text };
    }
    return { text };
  }

  /**
   * Signaling pipelines may return `[[…]]` (batch) or `[…]` (single) shapes.
   * Dim verification is deferred to callers via parseEmbeddingResult.
   */
  private parseEmbeddingResult(data: any): number[] | null {
    if (this.provider === "huggingface") {
      if (!Array.isArray(data)) return null;
      const first: unknown = data[0];
      const vector: unknown = Array.isArray(first) ? first : data;
      return Array.isArray(vector) ? vector : null;
    }
    const vector: unknown = data?.embedding;
    return Array.isArray(vector) ? vector : null;
  }

  passageText(title: string, description?: string | null): string {
    const parts = [title || ""];
    if (description) parts.push(description.trim());
    return `${this.passagePrefix}${parts.filter(Boolean).join(" ")}`;
  }

  queryText(raw: string): string {
    return `${this.queryPrefix}${(raw || "").trim()}`;
  }

  contentHash(title: string, description?: string | null): string {
    return createHash("sha256")
      .update(`${title || ""}|${description || ""}`)
      .digest("hex");
  }

  /**
   * Embeds a user query via the self-hosted embedding service. Returns null
   * when the service is unavailable, slow, or misconfigured so callers can
   * gracefully fall back to keyword search.
   */
  async embedQuery(raw: string): Promise<number[] | null> {
    if (!this.isEnabled) return null;

    const key = raw.trim().toLowerCase();
    const cached = this.cache.get(key);
    if (cached && Date.now() - cached.at < this.cacheTtlMs)
      return cached.vector;

    const text = this.queryText(raw);
    const started = Date.now();
    this.lastAttemptAt = started;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      let res: Response;
      try {
        res = await fetch(this.embedUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(this.authToken
              ? { Authorization: `Bearer ${this.authToken}` }
              : {}),
          },
          body: JSON.stringify(this.embedBody(text)),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timer);
      }

      if (!res.ok) {
        this.recordError(
          `Embedding service returned ${res.status}`,
          started,
        );
        return null;
      }

      const data: any = await res.json();
      const vector = this.parseEmbeddingResult(data);
      if (!vector || vector.length !== this.dim) {
        this.recordError(
          `Embedding service returned malformed vector (provider=${this.provider})`,
          started,
        );
        return null;
      }

      if (this.cache.size >= this.maxCacheEntries) {
        const oldest = this.cache.keys().next().value;
        if (oldest) this.cache.delete(oldest);
      }
      this.cache.set(key, { vector, at: Date.now() });
      this.lastError = null;
      this.lastSuccessAt = Date.now();
      this.lastCallMs = Date.now() - started;
      return vector;
    } catch (e: any) {
      const message = e?.message ?? "timeout";
      this.logger.warn(`Query embedding failed: ${message}`);
      this.recordError(message, started);
      return null;
    }
  }

  private recordError(message: string, startedAt: number) {
    this.lastError = message;
    this.lastCallMs = Date.now() - startedAt;
  }

  /**
   * Periodic reconciliation: when the model version is bumped, mark previously
   * completed embeddings as pending so the worker re-embeds them with the new
   * contract. New rows already default to 'pending'.
   */
  @Cron(CronExpression.EVERY_30_MINUTES)
  async reconcilePendingEmbeddings() {
    if (!this.enabled) return;
    try {
      const result = await this.prisma.$executeRawUnsafe(
        `UPDATE "Video"
         SET "embeddingStatus" = 'pending', "embeddingError" = NULL
         WHERE "embeddingStatus" = 'completed'
           AND ("embeddingVersion" IS NULL OR "embeddingVersion" <> $1)`,
        this.version,
      );
      if (result > 0) {
        this.logger.log(
          `Re-queued ${result} videos for embedding on contract version ${this.version}.`,
        );
      }
    } catch (e: any) {
      this.logger.warn(`Embedding reconcile note: ${e.message}`);
    }
  }
}
