import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../cache/cache.service';

@Injectable()
export class AdminPushService {
  private readonly logger = new Logger(AdminPushService.name);
  private firebaseApp: any = null;
  private initAttempted = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly cache: CacheService,
  ) {}

  private deviceTokensKey(): string {
    return `${this.cache.getPrefix()}:audio_proc:fcm_tokens`;
  }

  private ensureFirebase(): any {
    if (this.firebaseApp) return this.firebaseApp;
    if (this.initAttempted) return null;
    this.initAttempted = true;

    const rawJson =
      this.configService.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON') ||
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
      '';
    if (!rawJson.trim()) {
      return null;
    }

    try {
      // Dynamic require so backend boots cleanly even before firebase-admin is installed
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const admin = require('firebase-admin');
      const serviceAccount = JSON.parse(rawJson);
      if (admin.apps && admin.apps.length > 0) {
        this.firebaseApp = admin.app();
      } else {
        this.firebaseApp = admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
        });
      }
      this.logger.log('Firebase Admin SDK initialized for Admin FCM push');
      return this.firebaseApp;
    } catch (err: any) {
      this.logger.warn(`Firebase Admin init skipped/failed: ${err?.message || err}`);
      return null;
    }
  }

  isConfigured(): boolean {
    const rawJson =
      this.configService.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON') ||
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
      '';
    return rawJson.trim().length > 0;
  }

  async registerToken(token: string): Promise<void> {
    const clean = (token || '').trim();
    if (!clean) return;
    await this.cache.sadd(this.deviceTokensKey(), clean);
  }

  async unregisterToken(token: string): Promise<void> {
    const clean = (token || '').trim();
    if (!clean) return;
    await this.cache.srem(this.deviceTokensKey(), clean);
  }

  async getRegisteredTokenCount(): Promise<number> {
    const tokens = await this.cache.smembers(this.deviceTokensKey());
    return tokens.length;
  }

  async notifyNewVideo(video: { id: string; title: string; channelName: string }): Promise<void> {
    const app = this.ensureFirebase();
    if (!app) return;

    const tokens = await this.cache.smembers(this.deviceTokensKey());
    if (tokens.length === 0) return;

    try {
      const messaging = app.messaging();
      const response = await messaging.sendEachForMulticast({
        tokens,
        data: {
          type: 'new_video_audio',
          videoId: video.id,
          title: (video.title || '').slice(0, 120),
          channelName: (video.channelName || '').slice(0, 80),
        },
        android: {
          priority: 'high',
          ttl: 86400 * 1000,
          collapseKey: 'new_videos',
        },
      });

      // Auto-prune dead/unregistered tokens from Redis
      if (response?.responses) {
        for (let i = 0; i < response.responses.length; i++) {
          const r = response.responses[i];
          if (!r.success && r.error?.code) {
            const code = String(r.error.code);
            if (
              code.includes('registration-token-not-registered') ||
              code.includes('invalid-registration-token')
            ) {
              await this.unregisterToken(tokens[i]);
              this.logger.log(`Pruned dead FCM token (${code})`);
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`FCM multicast push failed: ${err?.message || err}`);
    }
  }
}
