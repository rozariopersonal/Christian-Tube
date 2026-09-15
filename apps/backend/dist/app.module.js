"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppModule = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const schedule_1 = require("@nestjs/schedule");
const configuration_1 = __importDefault(require("./config/configuration"));
const prisma_module_1 = require("./modules/prisma/prisma.module");
const users_module_1 = require("./modules/users/users.module");
const videos_module_1 = require("./modules/videos/videos.module");
const channels_module_1 = require("./modules/channels/channels.module");
const youtube_module_1 = require("./modules/youtube/youtube.module");
const sync_module_1 = require("./modules/sync/sync.module");
const transcription_module_1 = require("./modules/transcription/transcription.module");
const embedding_module_1 = require("./modules/embedding/embedding.module");
const storage_module_1 = require("./modules/storage/storage.module");
const health_module_1 = require("./modules/health/health.module");
const words_module_1 = require("./modules/words/words.module");
const shorts_module_1 = require("./modules/shorts/shorts.module");
const feedback_module_1 = require("./modules/feedback/feedback.module");
const admin_release_module_1 = require("./modules/admin-release/admin-release.module");
const audio_module_1 = require("./modules/audio/audio.module");
let AppModule = class AppModule {
};
exports.AppModule = AppModule;
exports.AppModule = AppModule = __decorate([
    (0, common_1.Module)({
        imports: [
            config_1.ConfigModule.forRoot({
                isGlobal: true,
                load: [configuration_1.default],
            }),
            schedule_1.ScheduleModule.forRoot(),
            health_module_1.HealthModule,
            prisma_module_1.PrismaModule,
            users_module_1.UsersModule,
            storage_module_1.StorageModule,
            videos_module_1.VideosModule,
            channels_module_1.ChannelsModule,
            youtube_module_1.YoutubeModule,
            sync_module_1.SyncModule,
            transcription_module_1.TranscriptionModule,
            embedding_module_1.EmbeddingModule,
            words_module_1.WordsModule,
            shorts_module_1.ShortsModule,
            feedback_module_1.FeedbackModule,
            admin_release_module_1.AdminReleaseModule,
            audio_module_1.AudioModule,
        ],
    })
], AppModule);
//# sourceMappingURL=app.module.js.map