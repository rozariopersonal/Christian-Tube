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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var SyncController_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SyncController = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const sync_service_1 = require("./sync.service");
let SyncController = SyncController_1 = class SyncController {
    constructor(syncService, configService) {
        this.syncService = syncService;
        this.configService = configService;
        this.logger = new common_1.Logger(SyncController_1.name);
    }
    verifyWebSubSubscription(mode, challenge, topic, res) {
        this.logger.log(`Google WebSub verification challenge (mode: ${mode}, topic: ${topic})`);
        if (challenge && res) {
            return res.status(200).send(challenge);
        }
        return res ? res.status(200).send('OK') : challenge || 'OK';
    }
    async handleWebSubPush(req, body, res) {
        const rawXml = typeof body === 'string' ? body : (req.rawBody || JSON.stringify(body));
        this.logger.log('Incoming Google WebSub real-time video push notification received.');
        this.syncService.handleWebSubPushNotification(rawXml).catch((err) => {
            this.logger.error(`Error processing WebSub push: ${err.message}`);
        });
        return res.status(204).send();
    }
    async triggerSync(secret) {
        const internalSecret = this.configService.get('internalJobSecret');
        if (internalSecret && secret && secret !== internalSecret) {
            throw new common_1.UnauthorizedException('Invalid job secret');
        }
        this.logger.log('Manual channel sync triggered via API endpoint.');
        this.syncService.syncAllChannels(true).catch((e) => {
            this.logger.error(`Manual sync error: ${e.message}`);
        });
        return {
            status: 'accepted',
            message: 'Channel sync process initiated in background',
            timestamp: new Date().toISOString(),
        };
    }
    async triggerChannelSync(id) {
        this.logger.log(`Manual sync triggered for channel: ${id}`);
        this.syncService.syncChannel(id).catch((e) => {
            this.logger.error(`Single channel sync error: ${e.message}`);
        });
        return {
            status: 'accepted',
            message: `Sync process initiated for channel ${id}`,
            timestamp: new Date().toISOString(),
        };
    }
    async triggerVideoSync(id) {
        this.logger.log(`Instant sync triggered for video: ${id}`);
        const video = await this.syncService.syncSingleVideo(id);
        return {
            status: video ? 'synced' : 'pending',
            video,
            timestamp: new Date().toISOString(),
        };
    }
    async triggerBackfill(secret) {
        const internalSecret = this.configService.get('internalJobSecret');
        if (internalSecret && secret && secret !== internalSecret) {
            throw new common_1.UnauthorizedException('Invalid job secret');
        }
        this.logger.log('Manual metadata backfill triggered via API endpoint.');
        this.syncService.backfillVideoMetadata(250).catch((e) => {
            this.logger.error(`Manual backfill error: ${e.message}`);
        });
        return {
            status: 'accepted',
            message: 'Video metadata backfill process initiated in background',
            timestamp: new Date().toISOString(),
        };
    }
};
exports.SyncController = SyncController;
__decorate([
    (0, common_1.Get)(['webhook', 'webhooks']),
    __param(0, (0, common_1.Query)('hub.mode')),
    __param(1, (0, common_1.Query)('hub.challenge')),
    __param(2, (0, common_1.Query)('hub.topic')),
    __param(3, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Object]),
    __metadata("design:returntype", void 0)
], SyncController.prototype, "verifyWebSubSubscription", null);
__decorate([
    (0, common_1.Post)(['webhook', 'webhooks']),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, Object]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "handleWebSubPush", null);
__decorate([
    (0, common_1.Get)(['', 'sync']),
    (0, common_1.Post)(['', 'sync']),
    __param(0, (0, common_1.Headers)('x-job-secret')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "triggerSync", null);
__decorate([
    (0, common_1.Post)('channel/:id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "triggerChannelSync", null);
__decorate([
    (0, common_1.Post)('video/:id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "triggerVideoSync", null);
__decorate([
    (0, common_1.Get)('backfill'),
    (0, common_1.Post)('backfill'),
    __param(0, (0, common_1.Headers)('x-job-secret')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "triggerBackfill", null);
exports.SyncController = SyncController = SyncController_1 = __decorate([
    (0, common_1.Controller)(['sync', 'youtube', 'api/sync', 'api/youtube']),
    __metadata("design:paramtypes", [sync_service_1.SyncService,
        config_1.ConfigService])
], SyncController);
//# sourceMappingURL=sync.controller.js.map