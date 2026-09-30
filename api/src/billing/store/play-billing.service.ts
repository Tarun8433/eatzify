import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { AllConfigType } from '../../config/config.type';
import { PlayClient } from './play.client';
import { StoreGrantService } from './store-grant.service';
import {
  purchaseNotActive,
  purchaseOtherAccount,
  storeNotConfigured,
} from './store-errors';
import {
  grantFromPlay,
  gstSplitMicros,
  storeAccountToken,
} from './store-rules';

/// Pub/Sub's push body. Only `message.data` (base64 JSON) is read.
export type PubSubPush = { message?: { data?: string } };

type PlayNotification = {
  packageName?: string;
  subscriptionNotification?: { purchaseToken?: string };
};

/// Google Play purchases (payments plan, Phase 4). The app never unlocks anything itself: it hands
/// the purchase token here, and the server asks Google what it is worth (docs/11 §5, rule 3).
@Injectable()
export class PlayBillingService {
  private readonly log = new Logger(PlayBillingService.name);

  constructor(
    private readonly play: PlayClient,
    private readonly grants: StoreGrantService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  /// `POST /billing/play/verify`, straight after a purchase on the phone.
  async verify(userId: number, token: string, now: Date): Promise<void> {
    this.requireConfigured();
    const grant = grantFromPlay(token, await this.play.subscription(token));
    if (!grant || grant.status === 'expired') throw purchaseNotActive();
    // The app attaches this account's token at purchase; one for another account is a replay.
    if (
      grant.accountToken &&
      grant.accountToken !== this.accountToken(userId)
    ) {
      throw purchaseOtherAccount();
    }

    await this.grants.apply(userId, grant, now);
    if (grant.needsAcknowledge) await this.acknowledge(grant.productId, token);
  }

  /// Real-time developer notifications: renewals, cancellations, refunds, grace, holds. The
  /// message is only a hint — the purchase is re-read from Google, so a forged one changes nothing.
  async notification(body: PubSubPush, now: Date): Promise<void> {
    if (!this.play.configured) return;
    const note = this.decode(body);
    const token = note?.subscriptionNotification?.purchaseToken;
    if (!token || note?.packageName !== this.play.packageName) return;

    const grant = grantFromPlay(token, await this.play.subscription(token));
    if (!grant) return;
    const row = await this.grants.apply(null, grant, now);
    if (row && grant.needsAcknowledge) {
      await this.acknowledge(grant.productId, token);
    }
  }

  /// User Choice Billing: the person picked Cashfree on Play's choice screen, and Google must be
  /// told about the sale within 24 hours. A failure is logged, never thrown — the payment is real
  /// and the plan is already active.
  async reportCashfreeSale(order: {
    id: string;
    amountPaise: string;
    externalTransactionToken: string | null;
    paidAt: Date | null;
  }): Promise<boolean> {
    if (!order.externalTransactionToken || !this.play.configured) return false;
    try {
      await this.play.reportExternalTransaction({
        id: order.id,
        externalTransactionToken: order.externalTransactionToken,
        ...gstSplitMicros(Number(order.amountPaise)),
        at: order.paidAt ?? new Date(),
      });
      return true;
    } catch (e) {
      this.log.error(
        `UCB report failed for order ${order.id}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
      return false;
    }
  }

  accountToken(userId: number): string {
    const pepper =
      this.config.get('app.trialPepper', { infer: true }) ?? 'eatzify-trial';
    return storeAccountToken(userId, pepper);
  }

  /// Unacknowledged purchases are refunded by Play after three days. A failure here is retried by
  /// the next notification or verify for the same token, so it is logged rather than thrown.
  private async acknowledge(productId: string, token: string): Promise<void> {
    try {
      await this.play.acknowledge(productId, token);
    } catch (e) {
      this.log.error(
        `acknowledge failed for ${productId}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
    }
  }

  private decode(body: PubSubPush): PlayNotification | null {
    const data = body?.message?.data;
    if (!data) return null;
    try {
      return JSON.parse(
        Buffer.from(data, 'base64').toString('utf8'),
      ) as PlayNotification;
    } catch {
      return null;
    }
  }

  private requireConfigured(): void {
    if (!this.play.configured) throw storeNotConfigured();
  }
}
