import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private s3Client: S3Client | null = null;
  private bucket: string;
  private publicUrl: string;

  constructor(private configService: ConfigService) {
    const storageConfig = this.configService.get('storage');
    if (storageConfig?.endpoint && storageConfig?.accessKey && storageConfig?.secretKey) {
      this.s3Client = new S3Client({
        region: storageConfig.region || 'auto',
        endpoint: storageConfig.endpoint,
        credentials: {
          accessKeyId: storageConfig.accessKey,
          secretAccessKey: storageConfig.secretKey,
        },
      });
      this.bucket = storageConfig.bucket;
      this.publicUrl = storageConfig.publicUrl;
      this.logger.log(`Cloudflare R2 Storage initialized for bucket: ${this.bucket}`);
    } else {
      this.logger.warn('Storage credentials not configured; S3 client disabled.');
    }
  }

  async uploadFile(key: string, body: Buffer | string, contentType: string): Promise<string> {
    if (!this.s3Client) {
      throw new Error('Storage client not initialized');
    }

    await this.s3Client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
      }),
    );

    return `${this.publicUrl}/${key}`;
  }
}
