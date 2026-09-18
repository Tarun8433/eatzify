import { ForbiddenException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SubscriptionEntity } from './entities/subscription.entity';
import { CashfreeClient } from './cashfree.client';
import {
  ENTITLED_STATUSES,
  entitlementsFor,
  PRICES,
  type Entitlements,
  type Tier,
} from './tiers';

export type SubscriptionView = {
  tier: Tier;
  status: string;
  current_period_end: string | null;
  entitlements: Entitlements;
  /// `stub` · `sandbox` · `production`. The app asks so its paywall can tell the truth: a build
  /// that cannot take money must not draw a pay button, and one that can must not say payments
  /// are coming soon. Rule 3's spirit — the server decides, the app renders.
  payments_mode: string;
};

@Injectable()
export class BillingService {
  constructor(
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly cashfree: CashfreeClient,
  ) {}

  /// docs/11 §4: resolved server-side, always. The client renders what it is told and never
  /// computes an entitlement (CLAUDE.md rule 3).
  ///
  /// An expired or cancelled subscription resolves to FREE rather than to nothing — everyone has
  /// entitlements, and the free tier is a real tier, not an absence.
  async entitlements(userId: number): Promise<SubscriptionView> {
    const row = await this.subscriptions.findOne({ where: { userId } });
    const tier = this.effectiveTier(row);

    return {
      tier,
      status: row?.status ?? 'active',
      current_period_end: row?.currentPeriodEnd?.toISOString() ?? null,
      entitlements: entitlementsFor(tier),
      payments_mode: this.cashfree.mode,
    };
  }

  /// Throws 403 ENTITLEMENT_REQUIRED, which the app answers with the upgrade sheet
  /// (CLAUDE.md rule 3).
  async require<K extends keyof Entitlements>(
    userId: number,
    key: K,
    userMessage: string,
  ): Promise<void> {
    const { entitlements } = await this.entitlements(userId);
    const value: boolean | number = entitlements[key];
    // A numeric entitlement (a daily count, a history window) is "allowed" when it is above zero;
    // a boolean speaks for itself.
    const allowed = typeof value === 'boolean' ? value : value > 0;

    if (!allowed) {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'ENTITLEMENT_REQUIRED',
          user_message: userMessage,
          details: { entitlement: key },
        },
      });
    }
  }

  /// The price list, so the app never hardcodes money. docs/11 §2 — paise, GST-inclusive.
  prices(): typeof PRICES {
    return PRICES;
  }

  /// A period end in the past means the row has lapsed even if a webhook has not arrived to say so
  /// — never trust a status field alone for something that expires with the clock.
  private effectiveTier(row: SubscriptionEntity | null): Tier {
    if (!row) return 'FREE';
    if (!(ENTITLED_STATUSES as readonly string[]).includes(row.status))
      return 'FREE';
    if (row.currentPeriodEnd && row.currentPeriodEnd.getTime() < Date.now()) {
      return 'FREE';
    }
    return row.tier as Tier;
  }
}
