"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var TranscriptionService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.TranscriptionService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const schedule_1 = require("@nestjs/schedule");
const generative_ai_1 = require("@google/generative-ai");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
let TranscriptionService = TranscriptionService_1 = class TranscriptionService {
    constructor(configService, prisma, storageService) {
        this.configService = configService;
        this.prisma = prisma;
        this.storageService = storageService;
        this.logger = new common_1.Logger(TranscriptionService_1.name);
        this.genAI = null;
        const apiKey = this.configService.get('geminiApiKey');
        this.modelName = this.configService.get('transcriptionModel') || 'gemini-3.1-flash-lite';
        this.enabled = this.configService.get('transcriptionEnabled') || false;
        if (apiKey) {
            this.genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
            this.logger.log(`Gemini AI Transcription Engine initialized with model: ${this.modelName}`);
        }
    }
    async processPendingTranscriptions() {
        if (!this.enabled || !this.genAI)
            return;
        const pendingVideos = await this.prisma.video.findMany({
            where: { transcriptionStatus: 'pending' },
            take: 2,
            orderBy: { createdAt: 'desc' },
        });
        if (!pendingVideos.length)
            return;
        this.logger.log(`Processing ${pendingVideos.length} pending video transcriptions...`);
        for (const video of pendingVideos) {
            try {
                await this.prisma.video.update({
                    where: { id: video.id },
                    data: { transcriptionStatus: 'processing' },
                });
                const model = this.genAI.getGenerativeModel({ model: this.modelName });
                const prompt = `Analyze this video titled "${video.title}" with description: "${video.description}". 
Provide a structured summary with:
1. Core Key Points / Key Scriptures / Concepts
2. Practical Reflections / Exercises
3. Full Transcript breakdown if available.`;
                const result = await model.generateContent(prompt);
                const text = result.response.text();
                try {
                    await this.storageService.uploadFile(`transcripts/${video.id}.txt`, text, 'text/plain');
                }
                catch (_) { }
                await this.prisma.video.update({
                    where: { id: video.id },
                    data: {
                        transcriptionStatus: 'completed',
                        content: text,
                        transcriptionProgress: 100,
                    },
                });
                this.logger.log(`Transcription completed for video: ${video.id}`);
            }
            catch (err) {
                this.logger.error(`Failed to transcribe video ${video.id}: ${err.message}`);
                await this.prisma.video.update({
                    where: { id: video.id },
                    data: {
                        transcriptionStatus: 'failed',
                        lastTranscriptionError: err.message,
                        transcriptionRetryCount: { increment: 1 },
                    },
                });
            }
        }
    }
};
exports.TranscriptionService = TranscriptionService;
__decorate([
    (0, schedule_1.Cron)(schedule_1.CronExpression.EVERY_5_MINUTES),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], TranscriptionService.prototype, "processPendingTranscriptions", null);
exports.TranscriptionService = TranscriptionService = TranscriptionService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService,
        prisma_service_1.PrismaService,
        storage_service_1.StorageService])
], TranscriptionService);
//# sourceMappingURL=transcription.service.js.map