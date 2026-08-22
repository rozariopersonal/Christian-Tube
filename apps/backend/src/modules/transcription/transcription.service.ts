import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';

@Injectable()
export class TranscriptionService {
  private readonly logger = new Logger(TranscriptionService.name);
  private genAI: GoogleGenerativeAI | null = null;
  private modelName: string;
  private enabled: boolean;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
  ) {
    const apiKey = this.configService.get<string>('geminiApiKey');
    this.modelName = this.configService.get<string>('transcriptionModel') || 'gemini-3.1-flash-lite';
    this.enabled = this.configService.get<boolean>('transcriptionEnabled') || false;

    if (apiKey) {
      this.genAI = new GoogleGenerativeAI(apiKey);
      this.logger.log(`Gemini AI Transcription Engine initialized with model: ${this.modelName}`);
    }
  }

  @Cron(CronExpression.EVERY_5_MINUTES)
  async processPendingTranscriptions() {
    if (!this.enabled || !this.genAI) return;

    const pendingVideos = await this.prisma.video.findMany({
      where: { transcriptionStatus: 'pending' },
      take: 2,
      orderBy: { createdAt: 'desc' },
    });

    if (!pendingVideos.length) return;

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

        // Optional: upload to Cloudflare R2
        try {
          await this.storageService.uploadFile(
            `transcripts/${video.id}.txt`,
            text,
            'text/plain',
          );
        } catch (_) {}

        await this.prisma.video.update({
          where: { id: video.id },
          data: {
            transcriptionStatus: 'completed',
            content: text,
            transcriptionProgress: 100,
          },
        });

        this.logger.log(`Transcription completed for video: ${video.id}`);
      } catch (err: any) {
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
}
