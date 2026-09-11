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
var StorageService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.StorageService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const client_s3_1 = require("@aws-sdk/client-s3");
let StorageService = StorageService_1 = class StorageService {
    constructor(configService) {
        this.configService = configService;
        this.logger = new common_1.Logger(StorageService_1.name);
        this.s3Client = null;
        const storageConfig = this.configService.get('storage');
        if (storageConfig?.endpoint && storageConfig?.accessKey && storageConfig?.secretKey) {
            this.s3Client = new client_s3_1.S3Client({
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
        }
        else {
            this.logger.warn('Storage credentials not configured; S3 client disabled.');
        }
    }
    async uploadFile(key, body, contentType) {
        if (!this.s3Client) {
            throw new Error('Storage client not initialized');
        }
        await this.s3Client.send(new client_s3_1.PutObjectCommand({
            Bucket: this.bucket,
            Key: key,
            Body: body,
            ContentType: contentType,
        }));
        return `${this.publicUrl}/${key}`;
    }
};
exports.StorageService = StorageService;
exports.StorageService = StorageService = StorageService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], StorageService);
//# sourceMappingURL=storage.service.js.map