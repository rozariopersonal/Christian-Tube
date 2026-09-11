"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var WordsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.WordsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
let WordsService = WordsService_1 = class WordsService {
    constructor(prisma) {
        this.prisma = prisma;
        this.logger = new common_1.Logger(WordsService_1.name);
    }
    async onModuleInit() {
        try {
            await this.seedDefaultWordsIfEmpty();
        }
        catch (e) {
            this.logger.warn(`Words initial check error: ${e.message}`);
        }
    }
    async seedDefaultWordsIfEmpty() {
        try {
            const count = await this.prisma.microFeedItem.count();
            if (count < 1000) {
                this.logger.log(`Current micro feed item count is ${count}. Seeding authentic scriptures into PostgreSQL database...`);
                await this.seedWords(false);
            }
            else {
                this.logger.log(`✅ Micro feed database already populated with ${count} items.`);
            }
        }
        catch (e) {
            this.logger.warn(`Could not verify/seed initial words: ${e.message}`);
        }
    }
    async seedWords(force = false) {
        if (force) {
            this.logger.warn('Force re-seeding: clearing existing MicroFeedItem records...');
            await this.prisma.microFeedItem.deleteMany({});
        }
        const jsonPath = path.join(process.cwd(), 'data', 'scriptures.json');
        if (!fs.existsSync(jsonPath)) {
            this.logger.error(`Seed file not found at ${jsonPath}`);
            return { message: 'Seed file not found', inserted: 0, total: 0 };
        }
        this.logger.log('Loading JSON payload into memory...');
        const rawData = fs.readFileSync(jsonPath, 'utf8');
        const allScriptures = JSON.parse(rawData);
        const chunkSize = 1000;
        let insertedCount = 0;
        for (let i = 0; i < allScriptures.length; i += chunkSize) {
            const chunk = allScriptures.slice(i, i + chunkSize);
            const data = chunk.map((item) => ({
                engine: item.engine || 'scripture',
                bookNumber: item.bookNumber,
                bookName: item.bookName,
                chapter: item.chapter,
                startVerse: item.startVerse,
                endVerse: item.endVerse,
                referenceLabel: item.referenceLabel,
                text: item.text,
                verseMappings: item.verseMappings || {},
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
            this.logger.log(`Seeded batch ${Math.floor(i / chunkSize) + 1}/${Math.ceil(allScriptures.length / chunkSize)} (+${res.count} records)`);
        }
        const totalInDb = await this.prisma.microFeedItem.count();
        this.logger.log(`✅ Micro feed seeding complete! Total items in database: ${totalInDb}`);
        return {
            message: 'Seeding completed successfully',
            inserted: insertedCount,
            total: totalInDb,
        };
    }
    async findAll(query) {
        const page = Math.max(1, query?.page ? Number(query.page) : 1);
        const limit = Math.max(1, Math.min(100, query?.limit ? Number(query.limit) : 25));
        const skip = (page - 1) * limit;
        const where = {};
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
        if (query?.seed != null) {
            const allItems = await this.prisma.microFeedItem.findMany({
                where,
                select: { id: true },
                orderBy: { id: 'asc' },
            });
            const total = allItems.length;
            let s = query.seed;
            const prng = () => {
                s = Math.sin(s) * 10000;
                return s - Math.floor(s);
            };
            for (let i = allItems.length - 1; i > 0; i--) {
                const j = Math.floor(prng() * (i + 1));
                const temp = allItems[i];
                allItems[i] = allItems[j];
                allItems[j] = temp;
            }
            const paginatedIds = allItems.slice(skip, skip + limit).map(i => i.id);
            const rawItems = await this.prisma.microFeedItem.findMany({
                where: { id: { in: paginatedIds } },
            });
            const itemMap = new Map(rawItems.map(i => [i.id, i]));
            const items = paginatedIds.map(id => itemMap.get(id)).filter(Boolean);
            return {
                total,
                page,
                limit,
                totalPages: Math.ceil(total / limit),
                items,
            };
        }
        else {
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
    }
    async create(data) {
        return this.prisma.microFeedItem.create({
            data: {
                engine: 'scripture',
                referenceLabel: data.referenceLabel,
                text: data.text,
                verseMappings: data.verseMappings,
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
    async remove(id) {
        return this.prisma.microFeedItem.delete({
            where: { id },
        });
    }
    async like(id) {
        return this.prisma.microFeedItem.update({
            where: { id },
            data: {
                likesCount: { increment: 1 },
            },
        });
    }
};
exports.WordsService = WordsService;
exports.WordsService = WordsService = WordsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], WordsService);
//# sourceMappingURL=words.service.js.map