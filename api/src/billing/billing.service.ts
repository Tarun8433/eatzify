import { PriceService, type PriceMatrix } from './price.service';
import { ForbiddenException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SubscriptionEntity } from './entities/subscription.entity';
import { CashfreeClient } from './cashfree.client';
import {
  ENTITLED_STATUSES,
  entitlementsFor,
  type Entitlements,
  type Tier,
} from './tiers';
import {
  type ClientPlatform,
  PAYMENTS_APP_STORE_MODE,
  PAYMENTS_PLAY_MODE,
  paymentsMode,
} from './payment-rails';
import { PlayClient } from './store/play.client';
import {
  appStoreProducts,
  playProducts,
  type AppStoreProductView,
  type PlayProductView,
} from './store/store-rules';
import { AppStoreClient } from './store/app-store.client';

export type SubscriptionView = {
  tier: Tier;
  status: string;
  current_period_end: string | null;
  entitlements: Entitlements;
  /// `stub` · `sandbox` · `production`. The app asks so its paywall can tell the truth: a build
  /// that cannot take money must not draw a pay button, and one that can must not say payments
  /// are coming soon. Rule 3's spirit — the server decides, the app renders.
  payments_mode: string;
  /// Only with `payments_mode: play`: the Play product and base plan for each cell of the price
  /// matrix, so the app never builds a store id itself (payments plan, Phase 4).
  play_products?: PlayProductView[];
  /// Only with `payments_mode: app_store`: the App Store product id per cell (Phase 5).
  appstore_products?: AppStoreProductView[];
};

@Injectable()
export class BillingService {
  constructor(
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly cashfree: CashfreeClient,
    private readonly priceService: PriceService,
    private readonly play: PlayClient,
    private readonly appStore: AppStoreClient,
  ) {}

  /// docs/11 §4: resolved server-side, always. The client renders what it is told and never
  /// computes an entitlement (CLAUDE.md rule 3).
  ///
  /// An expired or cancelled subscription resolves to FREE rather than to nothing — everyone has
  /// entitlements, and the free tier is a real tier, not an absence.
  async entitlements(
    userId: number,
    platform: ClientPlatform = 'unknown',
  ): Promise<SubscriptionView> {
    const row = await this.subscriptions.findOne({ where: { userId } });
    const tier = this.effectiveTier(row);
    // D-249: an app that may not offer Cashfree is told there is no way to pay here, so it draws
    // no pay button — rather than one that the checkout route would then refuse. Android goes to
    // Google Play instead once Play is configured (Phase 4).
    const mode = paymentsMode(
      this.cashfree.mode,
      platform,
      this.cashfree.androidEnabled,
      this.play.configured,
      this.appStore.configured,
    );

    return {
      tier,
      status: row?.status ?? 'active',
      current_period_end: row?.currentPeriodEnd?.toISOString() ?? null,
      entitlements: entitlementsFor(tier),
      payments_mode: mode,
      ...(mode === PAYMENTS_PLAY_MODE ? { play_products: playProducts() } : {}),
      ...(mode === PAYMENTS_APP_STORE_MODE
        ? { appstore_products: appStoreProducts() }
        : {}),
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
  prices(): Promise<PriceMatrix> {
    return this.priceService.matrix();
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
