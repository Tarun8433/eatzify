import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { google, type androidpublisher_v3 } from 'googleapis';
import type { AllConfigType } from '../../config/config.type';

const LIVE_PLANS_TTL_MS = 10 * 60_000;

/// The Google Play Developer API, and nothing else. Thin on purpose: every decision about what a
/// purchase means is in `store-rules.ts`, where it is tested without a network.
@Injectable()
export class PlayClient {
  private readonly log = new Logger(PlayClient.name);
  private api: androidpublisher_v3.Androidpublisher | null = null;
  private live: { at: number; plans: Set<string> } | null = null;

  constructor(private readonly config: ConfigService<AllConfigType>) {}

  get packageName(): string {
    return this.config.getOrThrow('store.playPackageName', { infer: true });
  }

  get configured(): boolean {
    return !!this.config.get('store.playServiceAccountFile', { infer: true });
  }

  /// The `product:basePlan` pairs Play is actually selling, asked of Play itself and remembered for
  /// ten minutes. The app is only sent to Play for these, so a plan missing or inactive in Play
  /// Console never becomes a Pay button that cannot open. A failed check sells nothing on Play.
  async liveBasePlans(
    productIds: string[],
    now = Date.now(),
  ): Promise<Set<string>> {
    if (this.live && now - this.live.at < LIVE_PLANS_TTL_MS)
      return this.live.plans;
    const plans = new Set<string>();
    try {
      for (const productId of productIds) {
        const res = await this.client()
          .monetization.subscriptions.get({
            packageName: this.packageName,
            productId,
          })
          .catch(() => null);
        for (const plan of res?.data.basePlans ?? []) {
          if (plan.state === 'ACTIVE' && plan.basePlanId) {
            plans.add(`${productId}:${plan.basePlanId}`);
          }
        }
      }
    } catch (e) {
      this.log.warn(
        `could not read Play subscriptions: ${e instanceof Error ? e.message : 'unknown'}`,
      );
    }
    this.live = { at: now, plans };
    return plans;
  }

  async subscription(
    token: string,
  ): Promise<androidpublisher_v3.Schema$SubscriptionPurchaseV2> {
    const res = await this.client().purchases.subscriptionsv2.get({
      packageName: this.packageName,
      token,
    });
    return res.data;
  }

  async acknowledge(productId: string, token: string): Promise<void> {
    await this.client().purchases.subscriptions.acknowledge({
      packageName: this.packageName,
      subscriptionId: productId,
      token,
    });
  }

  /// User Choice Billing: a purchase the user chose to pay outside Play must be reported to Google
  /// within 24 hours, or the app is out of policy.
  async reportExternalTransaction(input: {
    id: string;
    externalTransactionToken: string;
    preTaxMicros: string;
    taxMicros: string;
    at: Date;
  }): Promise<void> {
    await this.client().externaltransactions.createexternaltransaction({
      parent: `applications/${this.packageName}`,
      externalTransactionId: input.id,
      requestBody: {
        originalPreTaxAmount: {
          priceMicros: input.preTaxMicros,
          currency: 'INR',
        },
        originalTaxAmount: { priceMicros: input.taxMicros, currency: 'INR' },
        transactionTime: input.at.toISOString(),
        oneTimeTransaction: {
          externalTransactionToken: input.externalTransactionToken,
        },
        userTaxAddress: { regionCode: 'IN' },
      },
    });
  }

  private client(): androidpublisher_v3.Androidpublisher {
    if (this.api) return this.api;
    const keyFile = this.config.get('store.playServiceAccountFile', {
      infer: true,
    });
    if (!keyFile)
      throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is not set');
    this.api = google.androidpublisher({
      version: 'v3',
      auth: new google.auth.GoogleAuth({
        keyFile,
        scopes: ['https://www.googleapis.com/auth/androidpublisher'],
      }),
    });
    return this.api;
  }
}
