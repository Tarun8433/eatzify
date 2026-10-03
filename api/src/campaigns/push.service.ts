import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { cert, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { In, Repository } from 'typeorm';
import { DeviceTokenEntity } from './entities/device-token.entity';
import type { ChannelResult } from './entities/notification-campaign.entity';

/// FCM's batch limit.
const BATCH = 500;

/// Tokens FCM says will never work again; they are removed rather than retried forever.
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/// Push notifications through Firebase Cloud Messaging (admin panel plan, Phase C). Off until
/// `FIREBASE_SERVICE_ACCOUNT_FILE` names the service-account JSON on the server (never in git).
@Injectable()
export class PushService {
  private readonly log = new Logger(PushService.name);
  private app: App | null = null;

  constructor(
    @InjectRepository(DeviceTokenEntity)
    private readonly tokens: Repository<DeviceTokenEntity>,
  ) {}

  get configured(): boolean {
    return !!process.env.FIREBASE_SERVICE_ACCOUNT_FILE;
  }

  /// `POST /devices`. A token moves to whoever signed in on that phone last.
  async register(
    userId: number,
    token: string,
    platform: 'android' | 'ios',
  ): Promise<void> {
    await this.tokens.upsert(
      { userId, token, platform, lastSeenAt: new Date() },
      { conflictPaths: ['token'] },
    );
  }

  /// `POST /devices/unregister`, on sign-out. Only the caller's own token.
  async unregister(userId: number, token: string): Promise<void> {
    await this.tokens.delete({ userId, token });
  }

  async sendToUsers(
    userIds: number[],
    title: string,
    body: string,
    data: Record<string, string> = {},
  ): Promise<ChannelResult> {
    if (!this.configured || userIds.length === 0) return { sent: 0, failed: 0 };
    const rows = await this.tokens.find({ where: { userId: In(userIds) } });
    const result: ChannelResult = { sent: 0, failed: 0 };
    const dead: string[] = [];

    for (let i = 0; i < rows.length; i += BATCH) {
      const batch = rows.slice(i, i + BATCH).map((r) => r.token);
      const res = await getMessaging(this.firebase()).sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data,
      });
      result.sent += res.successCount;
      result.failed += res.failureCount;
      res.responses.forEach((r, j) => {
        if (!r.success && r.error && DEAD_TOKEN_CODES.has(r.error.code))
          dead.push(batch[j]);
      });
    }
    if (dead.length) {
      await this.tokens.delete({ token: In(dead) });
      this.log.log(`removed ${dead.length} dead push tokens`);
    }
    return result;
  }

  private firebase(): App {
    this.app ??= initializeApp(
      { credential: cert(process.env.FIREBASE_SERVICE_ACCOUNT_FILE!) },
      'eatzify-push',
    );
    return this.app;
  }
}
