import { ConfigService } from '@nestjs/config';
export declare class StorageService {
    private configService;
    private readonly logger;
    private s3Client;
    private bucket;
    private publicUrl;
    constructor(configService: ConfigService);
    uploadFile(key: string, body: Buffer | string, contentType: string): Promise<string>;
}
