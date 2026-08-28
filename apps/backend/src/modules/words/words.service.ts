import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ALL_SCRIPTURES } from './data/scriptures.data';

@Injectable()
export class WordsService implements OnModuleInit {
  private readonly logger = new Logger(WordsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    try {
      await this.seedDefaultWordsIfEmpty();
    } catch (e: any) {
      this.logger.warn(`Words initial check error: ${e.message}`);
    }
  }

  async seedDefaultWordsIfEmpty() {
    try {
      const count = await this.prisma.microFeedItem.count();
      if (count < 1000) {
        this.logger.log(
          `Current micro feed item count is ${count}. Seeding up to ${ALL_SCRIPTURES.length} authentic scriptures into PostgreSQL database...`,
        );
        await this.seedWords(false);
      } else {
        this.logger.log(`✅ Micro feed database already populated with ${count} items.`);
      }
    } catch (e: any) {
      this.logger.warn(`Could not verify/seed initial words: ${e.message}`);
    }
  }

  async seedWords(force: boolean = false) {
    if (force) {
      this.logger.warn('Force re-seeding: clearing existing MicroFeedItem records...');
      await this.prisma.microFeedItem.deleteMany({});
    }

    const chunkSize = 200;
    let insertedCount = 0;

    for (let i = 0; i < ALL_SCRIPTURES.length; i += chunkSize) {
      const chunk = ALL_SCRIPTURES.slice(i, i + chunkSize);
      const data = chunk.map((item) => ({
        engine: item.engine || 'scripture',
        bookNumber: item.bookNumber,
        bookName: item.bookName,
        chapter: item.chapter,
        startVerse: item.startVerse,
        endVerse: item.endVerse,
        referenceLabel: item.referenceLabel,
        text: item.text,
        translation: item.translation || 'WEB',
        category: item.category || 'General',
        backgroundPreset: item.backgroundPreset || 'mountain_dawn',
        tags: item.tags || [],
        isFeatured: item.isFeatured ?? false,
      }));

      const res = await this.prisma.microFeedItem.createMany({
        data,
        skipDuplicates: true,
      });

      insertedCount += res.count;
      this.logger.log(
        `Seeded batch ${Math.floor(i / chunkSize) + 1}/${Math.ceil(ALL_SCRIPTURES.length / chunkSize)} (+${res.count} records)`,
      );
    }

    const totalInDb = await this.prisma.microFeedItem.count();
    this.logger.log(`✅ Micro feed seeding complete! Total items in database: ${totalInDb}`);

    return {
      message: 'Seeding completed successfully',
      inserted: insertedCount,
      total: totalInDb,
    };
  }

  async findAll(query?: {
    category?: string;
    translation?: string;
    search?: string;
    page?: number;
    limit?: number;
  }) {
    const page = Math.max(1, query?.page ? Number(query.page) : 1);
    const limit = Math.max(1, Math.min(100, query?.limit ? Number(query.limit) : 25));
    const skip = (page - 1) * limit;

    const where: any = {};
    if (query?.category && query.category.toLowerCase() !== 'all') {
      where.category = { equals: query.category, mode: 'insensitive' };
    }
    if (query?.translation) {
      where.translation = { equals: query.translation, mode: 'insensitive' };
    }
    if (query?.search) {
      where.OR = [
        { text: { contains: query.search, mode: 'insensitive' } },
        { referenceLabel: { contains: query.search, mode: 'insensitive' } },
        { bookName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.microFeedItem.count({ where }),
      this.prisma.microFeedItem.findMany({
        where,
        skip,
        take: limit,
        orderBy: [{ isFeatured: 'desc' }, { createdAt: 'desc' }],
      }),
    ]);

    return {
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
      items,
    };
  }

  async create(data: {
    referenceLabel: string;
    text: string;
    translation?: string;
    category?: string;
    backgroundPreset?: string;
    bookName?: string;
    chapter?: number;
    startVerse?: number;
    endVerse?: number;
    tags?: string[];
    isFeatured?: boolean;
  }) {
    return this.prisma.microFeedItem.create({
      data: {
        engine: 'scripture',
        referenceLabel: data.referenceLabel,
        text: data.text,
        translation: data.translation || 'WEB',
        category: data.category || 'General',
        backgroundPreset: data.backgroundPreset || 'mountain_dawn',
        bookName: data.bookName,
        chapter: data.chapter,
        startVerse: data.startVerse,
        endVerse: data.endVerse,
        tags: data.tags || [],
        isFeatured: data.isFeatured ?? false,
      },
    });
  }

  async remove(id: string) {
    return this.prisma.microFeedItem.delete({
      where: { id },
    });
  }

  async like(id: string) {
    return this.prisma.microFeedItem.update({
      where: { id },
      data: {
        likesCount: { increment: 1 },
      },
    });
  }
}

