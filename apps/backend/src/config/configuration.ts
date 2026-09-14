import * as fs from 'fs';
import * as path from 'path';

export default () => {
  const instanceId = process.env.INSTANCE_ID || 'christian_tube';
  let instanceConfig: any = {};

  try {
    const configPath = path.resolve(__dirname, `../../../../instances/${instanceId}/config.json`);
    if (fs.existsSync(configPath)) {
      instanceConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    }
  } catch (e) {
    console.warn(`Could not load instance config for ${instanceId}:`, e);
  }

  const rawAdminEmails = process.env.ADMIN_EMAILS || 'admin@privatetube.org,admin@centumacademy.org,arul.rozario4@gmail.com,arul@example.com';
  const instanceAdminEmails: string[] = Array.isArray(instanceConfig.adminEmails) ? instanceConfig.adminEmails : [];
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
    embedding: {
      provider: process.env.EMBEDDING_PROVIDER || 'self-hosted',
      serviceUrl: process.env.EMBEDDING_SERVICE_URL,
      authToken: process.env.EMBEDDING_AUTH_TOKEN,
      model: process.env.EMBEDDING_MODEL || 'intfloat/multilingual-e5-small',
      dim: parseInt(process.env.EMBEDDING_DIM || '384', 10),
      version: parseInt(process.env.EMBEDDING_VERSION || '1', 10),
      timeoutMs: process.env.EMBEDDING_TIMEOUT_MS
        ? parseInt(process.env.EMBEDDING_TIMEOUT_MS, 10)
        : undefined,
      enabled: process.env.EMBEDDING_ENABLED !== 'false',
    },
    contentSearch: {
      enabled: process.env.CONTENT_SEARCH_ENABLED !== 'false',
      maxChunks: parseInt(process.env.CONTENT_SEARCH_MAX_CHUNKS || '60', 10),
    },
    internalJobSecret: process.env.INTERNAL_JOB_SECRET,
    githubToken: process.env.GITHUB_TOKEN || process.env.GITHUB_FEEDBACK_TOKEN,
    githubRepo: process.env.GITHUB_REPO || 'rozariopersonal/Christian-Tube',
    adminEmails,
    instanceConfig,
    seedChannels: [],
  };
};
