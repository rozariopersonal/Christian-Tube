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
Object.defineProperty(exports, "__esModule", { value: true });
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
exports.default = () => {
    const instanceId = process.env.INSTANCE_ID || 'christian_tube';
    let instanceConfig = {};
    try {
        const configPath = path.resolve(__dirname, `../../../../instances/${instanceId}/config.json`);
        if (fs.existsSync(configPath)) {
            instanceConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        }
    }
    catch (e) {
        console.warn(`Could not load instance config for ${instanceId}:`, e);
    }
    const rawAdminEmails = process.env.ADMIN_EMAILS || 'admin@privatetube.org,admin@centumacademy.org,arul.rozario4@gmail.com,arul@example.com';
    const instanceAdminEmails = Array.isArray(instanceConfig.adminEmails) ? instanceConfig.adminEmails : [];
    const adminEmails = Array.from(new Set([
        ...rawAdminEmails.split(',').map((e) => e.trim().toLowerCase()),
        ...instanceAdminEmails.map((e) => e.trim().toLowerCase()),
    ])).filter(Boolean);
    return {
        port: parseInt(process.env.PORT || '3000', 10),
        instanceId,
        appName: process.env.APP_NAME || instanceConfig.appName || 'PrivateTube',
        databaseUrl: process.env.DATABASE_URL,
        googleClientId: process.env.GOOGLE_CLIENT_ID || instanceConfig.googleClientId,
        youtubeApiKey: process.env.YOUTUBE_API_KEY,
        youtubeClientId: process.env.YOUTUBE_CLIENT_ID || instanceConfig.shorts?.youtubeClientId,
        youtubeClientSecret: process.env.YOUTUBE_CLIENT_SECRET || instanceConfig.shorts?.youtubeClientSecret,
        youtubeRefreshToken: process.env.YOUTUBE_REFRESH_TOKEN || instanceConfig.shorts?.youtubeRefreshToken,
        shorts: {
            enabled: instanceConfig.shorts?.enabled ?? true,
            customChannelId: process.env.SHORTS_CUSTOM_CHANNEL_ID || instanceConfig.shorts?.customChannelId || null,
            dailyQuotaUnits: instanceConfig.shorts?.dailyQuotaUnits || 10000,
            uploadCostUnits: instanceConfig.shorts?.uploadCostUnits || 1600,
            maxDurationSeconds: instanceConfig.shorts?.maxDurationSeconds || 180,
            defaultPrivacyStatus: instanceConfig.shorts?.defaultPrivacyStatus || 'unlisted',
            selfDeclaredMadeForKids: instanceConfig.shorts?.selfDeclaredMadeForKids ?? true,
        },
        geminiApiKey: process.env.GEMINI_API_KEY,
        transcriptionModel: process.env.TRANSCRIPTION_MODEL || 'gemini-3.1-flash-lite',
        transcriptionEnabled: process.env.TRANSCRIPTION_ENABLED === 'true',
        storage: {
            endpoint: process.env.STORAGE_ENDPOINT,
            region: process.env.STORAGE_REGION || 'auto',
            bucket: process.env.STORAGE_BUCKET,
            accessKey: process.env.STORAGE_ACCESS_KEY,
            secretKey: process.env.STORAGE_SECRET_KEY,
            publicUrl: process.env.STORAGE_PUBLIC_URL,
        },
        internalJobSecret: process.env.INTERNAL_JOB_SECRET,
        adminEmails,
        instanceConfig,
        seedChannels: [],
    };
};
//# sourceMappingURL=configuration.js.map