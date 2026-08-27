import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class WordsService implements OnModuleInit {
  private readonly logger = new Logger(WordsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    try {
      await this.seedDefaultWordsIfEmpty();
    } catch (e: any) {
      this.logger.warn(`Words initial check: ${e.message}`);
    }
  }

  async seedDefaultWordsIfEmpty() {
    try {
      const count = await this.prisma.microFeedItem.count();
      if (count === 0) {
        this.logger.log('Seeding initial curated Scripture & Words into PostgreSQL database...');
        const initialWords = [
          {
            engine: 'scripture',
            bookNumber: 43,
            bookName: 'John',
            chapter: 3,
            startVerse: 16,
            endVerse: 16,
            referenceLabel: 'John 3:16',
            text: 'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.',
            translation: 'WEB',
            category: 'Faith',
            backgroundPreset: 'mountain_dawn',
            tags: ['Love', 'Salvation', 'Eternal Life'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 19,
            bookName: 'Psalms',
            chapter: 23,
            startVerse: 1,
            endVerse: 3,
            referenceLabel: 'Psalm 23:1-3',
            text: 'Yahweh is my shepherd: I shall lack nothing. He makes me lie down in green pastures. He leads me beside still waters. He restores my soul.',
            translation: 'WEB',
            category: 'Peace',
            backgroundPreset: 'ocean_sunset',
            tags: ['Peace', 'Comfort', 'Provision'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 50,
            bookName: 'Philippians',
            chapter: 4,
            startVerse: 13,
            endVerse: 13,
            referenceLabel: 'Philippians 4:13',
            text: 'I can do all things through Christ, who strengthens me.',
            translation: 'WEB',
            category: 'Strength',
            backgroundPreset: 'aurora_sky',
            tags: ['Strength', 'Faith', 'Courage'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 20,
            bookName: 'Proverbs',
            chapter: 3,
            startVerse: 5,
            endVerse: 6,
            referenceLabel: 'Proverbs 3:5-6',
            text: 'Trust in Yahweh with all your heart, and don’t lean on your own understanding. In all your ways acknowledge him, and he will make your paths straight.',
            translation: 'WEB',
            category: 'Wisdom',
            backgroundPreset: 'forest_mist',
            tags: ['Trust', 'Guidance', 'Wisdom'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 24,
            bookName: 'Jeremiah',
            chapter: 29,
            startVerse: 11,
            endVerse: 11,
            referenceLabel: 'Jeremiah 29:11',
            text: '“For I know the thoughts that I think toward you,” says Yahweh, “thoughts of peace, and not of evil, to give you hope and a future.”',
            translation: 'WEB',
            category: 'Hope',
            backgroundPreset: 'golden_glow',
            tags: ['Hope', 'Future', 'Peace'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 45,
            bookName: 'Romans',
            chapter: 8,
            startVerse: 28,
            endVerse: 28,
            referenceLabel: 'Romans 8:28',
            text: 'We know that all things work together for good for those who love God, to those who are called according to his purpose.',
            translation: 'WEB',
            category: 'Encouragement',
            backgroundPreset: 'desert_starlight',
            tags: ['Purpose', 'Love', 'Gods Plan'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 23,
            bookName: 'Isaiah',
            chapter: 40,
            startVerse: 31,
            endVerse: 31,
            referenceLabel: 'Isaiah 40:31',
            text: 'But those who wait for Yahweh will renew their strength. They will mount up with wings like eagles. They will run, and not be weary. They will walk, and not faint.',
            translation: 'WEB',
            category: 'Strength',
            backgroundPreset: 'celestial_nebula',
            tags: ['Hope', 'Strength', 'Patience'],
            isFeatured: true,
          },
          {
            engine: 'scripture',
            bookNumber: 40,
            bookName: 'Matthew',
            chapter: 11,
            startVerse: 28,
            endVerse: 28,
            referenceLabel: 'Matthew 11:28',
            text: '“Come to me, all you who labor and are heavily burdened, and I will give you rest.”',
            translation: 'WEB',
            category: 'Rest',
            backgroundPreset: 'ocean_sunset',
            tags: ['Rest', 'Jesus', 'Peace'],
            isFeatured: true,
          },
        ];

        for (const w of initialWords) {
          await this.prisma.microFeedItem.create({ data: w });
        }
        this.logger.log(`✅ Seeded ${initialWords.length} micro feed items successfully.`);
      }
    } catch (e: any) {
      this.logger.warn(`Could not seed initial words: ${e.message}`);
    }
  }

  async findAll(query?: {
    category?: string;
    translation?: string;
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
