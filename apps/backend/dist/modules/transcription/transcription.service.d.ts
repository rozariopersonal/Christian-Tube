import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
export declare class TranscriptionService {
    private readonly configService;
    private readonly prisma;
    private readonly storageService;
    private readonly logger;
    private genAI;
    private modelName;
    private enabled;
    constructor(configService: ConfigService, prisma: PrismaService, storageService: StorageService);
    processPendingTranscriptions(): Promise<void>;
}
