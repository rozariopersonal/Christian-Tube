import * as fs from 'fs';
import * as path from 'path';

export default () => {
  const instanceId = process.env.INSTANCE_ID || 'christian_tube';
  let instanceConfig: any = {};
  let seedChannels: any[] = [];

  try {
    const configPath = path.resolve(__dirname, `../../../../instances/${instanceId}/config.json`);
    if (fs.existsSync(configPath)) {
      instanceConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    }
  } catch (e) {
    console.warn(`Could not load instance config for ${instanceId}:`, e);
  }

  try {
    const seedsPath = path.resolve(__dirname, `../../../../instances/${instanceId}/seed_channels.json`);
    if (fs.existsSync(seedsPath)) {
      seedChannels = JSON.parse(fs.readFileSync(seedsPath, 'utf8'));
    }
  } catch (e) {
    console.warn(`Could not load seed channels for ${instanceId}:`, e);
  }

  return {
    port: parseInt(process.env.PORT || '3000', 10),
    instanceId,
    appName: process.env.APP_NAME || instanceConfig.appName || 'PrivateTube',
    databaseUrl: process.env.DATABASE_URL,
    youtubeApiKey: process.env.YOUTUBE_API_KEY,
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
    instanceConfig,
    seedChannels,
  };
};
