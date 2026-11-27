import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

export interface UserItemDto {
  id?: string;
  itemType: string;
  feature?: string;
  targetId?: string;
  versionId?: string;
  book?: string;
  chapter?: number;
  verseStart?: number;
  verseEnd?: number;
  startOffset?: number;
  endOffset?: number;
  color?: string | null;
  colorIndex?: number | null;
  text?: string;
  contextText?: string | null;
  payloadJson?: string | null;
  deleted?: boolean;
  isDeleted?: boolean;
  updatedAt?: string | number | Date;
  clientUpdatedAt?: string | number | Date;
  createdAt?: string | number | Date;
}

const VALID_ITEM_TYPES = new Set([
  'highlight',
  'bookmark',
  'note',
  'text_range',
]);

const VALID_FEATURES = new Set(['bible', 'book', 'article', 'video', 'short']);

@Injectable()
export class UserItemsService {
  private readonly logger = new Logger(UserItemsService.name);

  constructor(private readonly prisma: PrismaService) {}

  private clampTimestamp(raw?: number | string | Date | null): Date {
    const now = Date.now();
    const maxAllowed = now + 60_000;
    if (raw === undefined || raw === null || raw === '') return new Date(now);
    const parsed =
      raw instanceof Date
        ? raw.getTime()
        : typeof raw === 'number'
          ? raw
          : Date.parse(String(raw));
    if (!Number.isFinite(parsed) || parsed <= 0) return new Date(now);
    return new Date(Math.min(parsed, maxAllowed));
  }

  private async ensureUser(userId: string, email?: string | null) {
    const cleanEmail = (email || '').trim().toLowerCase();
    if (!cleanEmail) {
      if (typeof (this.prisma.user as any)?.findUnique === 'function') {
        const existing = await (this.prisma.user as any).findUnique({
          where: { id: userId },
        });
        if (existing) {
          return existing;
        }
      }
      throw new BadRequestException('Valid email is required to create user');
    }

    try {
      await this.prisma.user.upsert({
        where: { id: userId },
        update: {
          email: cleanEmail,
          lastLoginAt: new Date(),
        },
        create: {
          id: userId,
          email: cleanEmail,
          role: 'USER',
          displayName: 'User',
          isBlocked: false,
          lastLoginAt: new Date(),
        },
      });
    } catch (err: any) {
      if (err?.code === 'P2002' && typeof (this.prisma.user as any)?.findUnique === 'function') {
        const existing = await (this.prisma.user as any).findUnique({
          where: { id: userId },
        });
        if (existing) {
          return existing;
        }
      }
      throw err;
    }
  }

  async listItems(
    userId: string,
    opts?: { after?: string; feature?: string },
  ) {
    const serverTime = Date.now();
    const where: any = { userId };
    if (opts?.feature && VALID_FEATURES.has(opts.feature)) {
      where.feature = opts.feature;
    }
    if (opts?.after) {
      const afterMs = Date.parse(opts.after);
      if (Number.isFinite(afterMs)) {
        where.clientUpdatedAt = { gt: new Date(afterMs) };
      }
    }

    const model = (this.prisma as any).userItem;
    const rows: any[] = model?.findMany
      ? await model.findMany({
          where,
          orderBy: { clientUpdatedAt: 'desc' },
          take: 2000,
        })
      : [];

    return {
      serverTime,
      items: rows.map((r) => this.serializeRow(r)),
    };
  }

  async upsertBatch(
    userId: string,
    userEmail: string | null | undefined,
    items: UserItemDto[],
  ) {
    await this.ensureUser(userId, userEmail);

    const results: Array<{ id: string; status: 'ok' | 'rejected' | 'retry' }> = [];
    for (const raw of items) {
      const id = (raw?.id || '').trim() || randomUUID();
      const itemType = (raw?.itemType || '').trim();
      const feature = (raw?.feature || 'bible').trim();
      if (!VALID_ITEM_TYPES.has(itemType) || !VALID_FEATURES.has(feature)) {
        results.push({ id, status: 'rejected' });
        continue;
      }

      try {
        await this.upsertSingleAtomic(userId, { ...raw, id, itemType, feature });
        results.push({ id, status: 'ok' });
      } catch (err: any) {
        if (err?.status === 400 || err?.status === 404) {
          results.push({ id, status: 'rejected' });
        } else {
          this.logger.warn(`UserItem upsert retry (${id}): ${err?.message || err}`);
          results.push({ id, status: 'retry' });
        }
      }
    }

    return { serverTime: Date.now(), results };
  }

  private async upsertSingleAtomic(userId: string, dto: UserItemDto & { id: string; itemType: string; feature: string }) {
    const ts = this.clampTimestamp(dto.clientUpdatedAt ?? dto.updatedAt);
    const createdAt = dto.createdAt ? this.clampTimestamp(dto.createdAt) : ts;
    const isDeleted = Boolean(dto.isDeleted ?? dto.deleted);
    const targetId = (dto.targetId ?? '').trim();
    const versionId = dto.versionId ?? '';
    const book = dto.book ?? '';
    const chapter = Math.max(0, Math.round(dto.chapter ?? 0));
    const verseStart = Math.max(0, Math.round(dto.verseStart ?? 0));
    const verseEnd = Math.max(0, Math.round(dto.verseEnd ?? 0));
    const startOffset = Math.max(0, Math.round(dto.startOffset ?? 0));
    const endOffset = Math.max(0, Math.round(dto.endOffset ?? 0));
    const color = dto.color ?? null;
    const colorIndex = dto.colorIndex ?? null;
    const text = dto.text ?? '';
    const contextText = dto.contextText ?? null;
    const payloadJson = dto.payloadJson ?? null;

    if (typeof (this.prisma as any).$executeRaw === 'function') {
      await (this.prisma as any).$executeRaw(
        Prisma.sql`
          INSERT INTO "UserItem" (
            "id", "userId", "itemType", "feature", "targetId",
            "versionId", "book", "chapter", "verseStart", "verseEnd",
            "startOffset", "endOffset", "color", "colorIndex",
            "text", "contextText", "payloadJson",
            "isDeleted", "clientUpdatedAt", "createdAt"
          )
          VALUES (
            ${dto.id}, ${userId}, ${dto.itemType}, ${dto.feature}, ${targetId},
            ${versionId}, ${book}, ${chapter}, ${verseStart}, ${verseEnd},
            ${startOffset}, ${endOffset}, ${color}, ${colorIndex},
            ${text}, ${contextText}, ${payloadJson},
            ${isDeleted}, ${ts}, ${createdAt}
          )
          ON CONFLICT ("userId", "id") DO UPDATE
          SET "itemType" = EXCLUDED."itemType",
              "feature" = EXCLUDED."feature",
              "targetId" = EXCLUDED."targetId",
              "versionId" = EXCLUDED."versionId",
              "book" = EXCLUDED."book",
              "chapter" = EXCLUDED."chapter",
              "verseStart" = EXCLUDED."verseStart",
              "verseEnd" = EXCLUDED."verseEnd",
              "startOffset" = EXCLUDED."startOffset",
              "endOffset" = EXCLUDED."endOffset",
              "color" = EXCLUDED."color",
              "colorIndex" = EXCLUDED."colorIndex",
              "text" = EXCLUDED."text",
              "contextText" = EXCLUDED."contextText",
              "payloadJson" = COALESCE(EXCLUDED."payloadJson", "UserItem"."payloadJson"),
              "isDeleted" = EXCLUDED."isDeleted",
              "clientUpdatedAt" = EXCLUDED."clientUpdatedAt"
          WHERE "UserItem"."clientUpdatedAt" <= EXCLUDED."clientUpdatedAt"
        `,
      );
      return;
    }

    const model = (this.prisma as any).userItem;
    if (!model) return;

    if (typeof model.createMany === 'function') {
      await model.createMany({
        data: [
          {
            id: dto.id,
            userId,
            itemType: dto.itemType,
            feature: dto.feature,
            targetId,
            versionId,
            book,
            chapter,
            verseStart,
            verseEnd,
            startOffset,
            endOffset,
            color,
            colorIndex,
            text,
            contextText,
            payloadJson,
            isDeleted,
            clientUpdatedAt: ts,
            createdAt,
          },
        ],
        skipDuplicates: true,
      });
    }

    if (typeof model.updateMany === 'function') {
      await model.updateMany({
        where: {
          userId,
          id: dto.id,
          clientUpdatedAt: { lte: ts },
        },
        data: {
          itemType: dto.itemType,
          feature: dto.feature,
          targetId,
          versionId,
          book,
          chapter,
          verseStart,
          verseEnd,
          startOffset,
          endOffset,
          color,
          colorIndex,
          text,
          contextText,
          ...(payloadJson !== null ? { payloadJson } : {}),
          isDeleted,
          clientUpdatedAt: ts,
        },
      });
    }
  }

  private serializeRow(r: any) {
    return {
      userId: r.userId,
      id: r.id,
      itemType: r.itemType,
      feature: r.feature,
      targetId: r.targetId,
      versionId: r.versionId ?? '',
      book: r.book ?? '',
      chapter: r.chapter ?? 0,
      verseStart: r.verseStart ?? 0,
      verseEnd: r.verseEnd ?? 0,
      startOffset: r.startOffset ?? 0,
      endOffset: r.endOffset ?? 0,
      color: r.color ?? null,
      colorIndex: r.colorIndex ?? null,
      text: r.text ?? '',
      contextText: r.contextText ?? null,
      payloadJson: r.payloadJson ?? null,
      deleted: Boolean(r.isDeleted),
      updatedAt: new Date(r.clientUpdatedAt).toISOString(),
      createdAt: new Date(r.createdAt).toISOString(),
    };
  }
}
