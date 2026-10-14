import {
  ConflictException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Request,
  Res,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import {
  ATTEMPT_OUTCOMES,
  ATTEMPT_PROVIDERS,
  ATTEMPT_REASONS,
  type AttemptOutcome,
  type AttemptReason,
} from './entities/store-purchase-attempt.entity';
import { StoreAttemptsService } from './store/store-attempts.service';
import type { StoreProvider } from './store/store-rules';
import { AuthGuard } from '@nestjs/passport';
import type { Response } from 'express';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { BillingService, type SubscriptionView } from './billing.service';
import {
  CheckoutService,
  type CheckoutView,
  type Duration,
} from './checkout.service';
import {
  SubscriptionService,
  type SubscriptionStateView,
  type UpgradeQuoteView,
} from './subscription.service';
import { RefundService, type RefundView } from './refund.service';
import {
  RefundRequestService,
  type PaidOrderView,
  type RefundRequestView,
} from './refund-request.service';
import { CashfreeClient } from './cashfree.client';
import { CashfreeMode } from './cashfree.config';
import {
  OFFER_NOT_PAYABLE,
  PAYMENTS_NOT_OFFERED,
  STUB_MODE,
} from './billing-copy';
import { type Tier } from './tiers';
import { type PriceMatrix } from './price.service';
import { PlayBillingService } from './store/play-billing.service';
import { AppStoreBillingService } from './store/app-store-billing.service';
import { InvoiceService, type InvoiceView } from './invoice/invoice.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { cashfreeOffered, platformFrom } from './payment-rails';
import {
  PersonalOffersService,
  type AppOfferView,
} from './offers/personal-offers.service';

// D-248: 9 months is no longer sold — Google Play and the App Store cannot bill it, and one plan
// list on every payment method is what users see.
const DURATIONS = ['1M', '3M', '6M', '12M'] as const;

class CheckoutDto {
  /// FREE is absent on purpose: there is nothing to buy, and accepting it would create a ₹0 order.
  @IsIn(['BASIC', 'PRO'])
  tier: Exclude<Tier, 'FREE'>;

  @IsIn([...DURATIONS])
  duration: Duration;

  /// D-236: an offer code. Optional; the server prices it, the body never names an amount.
  @IsOptional()
  @IsString()
  coupon_code?: string;

  /// User Choice Billing: Play's token when the person chose Cashfree on Play's choice screen.
  @IsOptional()
  @IsString()
  @MaxLength(1024)
  external_transaction_token?: string;
}

class PlayVerifyDto {
  @IsString()
  @MaxLength(1024)
  purchase_token: string;

  /// D-265: the personal offer this purchase was made from, if any. Only marks the link spent —
  /// the purchase itself never depends on it, because Play has already enforced the price.
  @IsOptional()
  @IsString()
  @MaxLength(64)
  offer_code?: string;
}

class AppStoreVerifyDto {
  /// StoreKit 2's `jwsRepresentation` of the transaction.
  @IsString()
  @MaxLength(16384)
  signed_transaction: string;
}

/// D-266: how one store purchase attempt ended, as the app saw it. Never names an amount; the user
/// is the caller, never a body field.
export class StoreAttemptDto {
  @IsIn([...ATTEMPT_PROVIDERS])
  provider: StoreProvider;

  @IsString()
  @MaxLength(100)
  product_id: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  base_plan_id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  offer_id?: string;

  @IsIn([...ATTEMPT_OUTCOMES])
  outcome: AttemptOutcome;

  @IsOptional()
  @IsIn([...ATTEMPT_REASONS])
  reason?: AttemptReason;

  /// Play's raw code. Anything not shaped like one is stored as null rather than refused.
  @IsOptional()
  @IsString()
  @MaxLength(200)
  store_code?: string;
}

class SimulateDto {
  @IsString()
  order_id: string;
}

class TrialDto {
  @IsIn(['BASIC', 'PRO'])
  tier: Exclude<Tier, 'FREE'>;
}

class CancelDto {
  /// Why they left, for the product's own reading. Optional: nobody owes an explanation.
  @IsString()
  @IsOptional()
  @MaxLength(500)
  reason?: string;
}

class UpgradeDto {
  @IsIn(['BASIC', 'PRO'])
  tier: Exclude<Tier, 'FREE'>;

  @IsIn([...DURATIONS])
  duration: Duration;
}

class RefundRequestDto {
  @IsString()
  order_id: string;

  /// Why — the person's own words, read by whoever decides (admin panel plan, Phase B).
  @IsString()
  @MaxLength(1000)
  reason: string;
}

class RefundDto {
  @IsString()
  order_id: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  reason?: string;
}

@ApiTags('Billing')
@ApiBearerAuth()
@Controller({ path: 'billing', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class BillingController {
  constructor(
    private readonly service: BillingService,
    private readonly checkout: CheckoutService,
    private readonly subscriptions: SubscriptionService,
    private readonly refunds: RefundService,
    private readonly refundRequests: RefundRequestService,
    private readonly cashfree: CashfreeClient,
    private readonly play: PlayBillingService,
    private readonly appStore: AppStoreBillingService,
    private readonly invoices: InvoiceService,
    private readonly personalOffers: PersonalOffersService,
    private readonly storeAttempts: StoreAttemptsService,
  ) {}

  /// docs/09 §7: the current state, its renewal date, and whether renewing needs AFA.
  @Get('subscription')
  @HttpCode(HttpStatus.OK)
  public subscription(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<SubscriptionStateView> {
    return this.subscriptions.state(Number(request.user.id), new Date());
  }

  /// docs/11 §6: the one free week, keyed to the account's number for life.
  @Post('trial')
  @HttpCode(HttpStatus.OK)
  public trial(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: TrialDto,
  ): Promise<SubscriptionStateView> {
    return this.subscriptions.startTrial(
      Number(request.user.id),
      dto.tier,
      new Date(),
    );
  }

  /// docs/09 §7: stops the renewal, keeps the access already paid for.
  @Post('cancel')
  @HttpCode(HttpStatus.OK)
  public cancel(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: CancelDto,
  ): Promise<SubscriptionStateView> {
    return this.subscriptions.cancel(
      Number(request.user.id),
      dto.reason ?? null,
      new Date(),
    );
  }

  /// docs/11 §7's arithmetic, before anything is charged. The confirm step is the checkout that
  /// follows it.
  @Post('upgrade/quote')
  @HttpCode(HttpStatus.OK)
  public upgradeQuote(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: UpgradeDto,
  ): Promise<UpgradeQuoteView> {
    return this.subscriptions.upgradeQuote(
      Number(request.user.id),
      dto.tier,
      dto.duration,
      new Date(),
    );
  }

  /// docs/11 §4.
  @Get('entitlements')
  @HttpCode(HttpStatus.OK)
  public entitlements(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Headers('X-Client-Platform') platform?: string,
  ): Promise<SubscriptionView> {
    return this.service.entitlements(
      Number(request.user.id),
      platformFrom(platform),
    );
  }

  /// docs/11 §7: charges the difference the quote named, and closes the period it replaces when
  /// the payment lands. A credit that covers the whole price settles without a gateway.
  @Post('upgrade')
  @HttpCode(HttpStatus.OK)
  public upgrade(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: UpgradeDto,
    @Headers('Idempotency-Key') idempotencyKey?: string,
    @Headers('X-Client-Platform') platform?: string,
  ): Promise<CheckoutView> {
    this.refuseUnlessCashfreeOffered(platform);
    return this.checkout.upgrade({
      userId: Number(request.user.id),
      tier: dto.tier,
      duration: dto.duration,
      idempotencyKey: idempotencyKey ?? null,
      now: new Date(),
    });
  }

  /// docs/11 §9: seven days, self-serve, for what we billed ourselves. The commission it earned is
  /// reversed with it (docs/12 §3).
  @Post('refund')
  @HttpCode(HttpStatus.OK)
  public refund(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: RefundDto,
  ): Promise<RefundView> {
    return this.refunds.refund(
      Number(request.user.id),
      dto.order_id,
      dto.reason ?? null,
      new Date(),
    );
  }

  /// The caller's own payments with the refund each allows (admin panel plan, Phase B).
  @Get('payments')
  public paidOrders(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<PaidOrderView[]> {
    return this.refundRequests.paidOrdersFor(
      Number(request.user.id),
      new Date(),
    );
  }

  /// Past the 7-day window: ask instead, and someone in finance decides (admin panel plan, Phase B).
  @Post('refund-request')
  @HttpCode(HttpStatus.CREATED)
  public requestRefund(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: RefundRequestDto,
  ): Promise<RefundRequestView> {
    return this.refundRequests.request(
      Number(request.user.id),
      dto.order_id,
      dto.reason,
      new Date(),
    );
  }

  /**
   * Start a purchase. Creates an order; it does not grant anything.
   *
   * The tier and duration name a cell in the price matrix and the server reads the amount from it
   * — the body never carries a price.
   */
  @Post('checkout')
  @HttpCode(HttpStatus.OK)
  public startCheckout(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: CheckoutDto,
    @Headers('Idempotency-Key') idempotencyKey?: string,
    @Headers('X-Client-Platform') platform?: string,
  ): Promise<CheckoutView> {
    this.refuseUnlessCashfreeOffered(platform);
    return this.checkout.checkout({
      userId: Number(request.user.id),
      tier: dto.tier,
      duration: dto.duration,
      idempotencyKey: idempotencyKey ?? null,
      now: new Date(),
      couponCode: dto.coupon_code ?? null,
      externalTransactionToken: dto.external_transaction_token ?? null,
    });
  }

  /// Payments plan, Phase 4: a Google Play purchase, checked with Google before anything is
  /// granted. Answers with the subscription as it now stands.
  @Post('play/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyPlay(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: PlayVerifyDto,
  ): Promise<SubscriptionStateView> {
    const userId = Number(request.user.id);
    const now = new Date();
    const line = await this.play.verify(userId, dto.purchase_token, now);
    if (dto.offer_code) {
      await this.personalOffers.markUsedByPlay(
        userId,
        dto.offer_code,
        line,
        now,
      );
    }
    return this.subscriptions.state(userId, now);
  }

  /// D-266: a store purchase attempt, kept for support. 204 always — past the hourly limit the
  /// attempt is dropped, because the app must never break on a report.
  @Post('store/attempts')
  @HttpCode(HttpStatus.NO_CONTENT)
  public async storeAttempt(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: StoreAttemptDto,
  ): Promise<void> {
    await this.storeAttempts.record(Number(request.user.id), {
      provider: dto.provider,
      productId: dto.product_id,
      basePlanId: dto.base_plan_id ?? null,
      offerId: dto.offer_id ?? null,
      outcome: dto.outcome,
      reason: dto.reason ?? null,
      storeCode: dto.store_code ?? null,
    });
  }

  /// D-265: a personal offer, the caller's own and still live; 404 for every other case alike.
  @Get('offers/:code')
  public async personalOffer(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('code') code: string,
    @Headers('X-Client-Platform') platform?: string,
  ): Promise<AppOfferView> {
    const offer = await this.personalOffers.forCaller(
      Number(request.user.id),
      code,
      new Date(),
    );
    // A Cashfree offer this app may not pay (D-249) is not shown with a Buy button that the
    // checkout would then refuse: it is answered here, in words, before the person tries.
    if (
      offer.channel === 'cashfree' &&
      !cashfreeOffered(
        this.cashfree.mode,
        platformFrom(platform),
        this.cashfree.androidEnabled,
      )
    ) {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: { code: 'OFFER_NOT_PAYABLE', user_message: OFFER_NOT_PAYABLE },
      });
    }
    return offer;
  }

  /// D-265: pay for a Cashfree personal offer. Same gate and same answer as `POST /checkout`; the
  /// amount is the offer's, read from its row.
  @Post('offers/:code/checkout')
  @HttpCode(HttpStatus.OK)
  public personalOfferCheckout(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('code') code: string,
    @Headers('Idempotency-Key') idempotencyKey?: string,
    @Headers('X-Client-Platform') platform?: string,
  ): Promise<CheckoutView> {
    this.refuseUnlessCashfreeOffered(platform);
    return this.personalOffers.startCheckout(
      Number(request.user.id),
      code,
      idempotencyKey ?? null,
      new Date(),
    );
  }

  /// D-255: this account's GST invoices and credit notes, newest first. Empty until the business
  /// is GST-registered and the seller details are configured.
  @Get('invoices')
  public invoiceList(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<InvoiceView[]> {
    return this.invoices.listFor(Number(request.user.id));
  }

  /// One invoice as a PDF, the caller's own only.
  @Get('invoices/:id/pdf')
  public async invoicePdf(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id', ParseUUIDPipe) id: string,
    @Res() res: Response,
  ): Promise<void> {
    const { number, pdf } = await this.invoices.pdfFor(
      Number(request.user.id),
      id,
    );
    res.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${number}.pdf"`,
    });
    res.send(pdf);
  }

  /// Payments plan, Phase 5: an App Store purchase. Apple's signature is checked and the
  /// subscription re-read from Apple before anything is granted.
  @Post('appstore/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyAppStore(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: AppStoreVerifyDto,
  ): Promise<SubscriptionStateView> {
    const userId = Number(request.user.id);
    const now = new Date();
    await this.appStore.verify(userId, dto.signed_transaction, now);
    return this.subscriptions.state(userId, now);
  }

  /// D-249: the pay button is already absent where Cashfree may not be offered; this refuses the
  /// request itself, because a hidden button does not stop a direct call.
  private refuseUnlessCashfreeOffered(platform?: string): void {
    if (
      !cashfreeOffered(
        this.cashfree.mode,
        platformFrom(platform),
        this.cashfree.androidEnabled,
      )
    ) {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'PAYMENTS_NOT_OFFERED',
          user_message: PAYMENTS_NOT_OFFERED,
        },
      });
    }
  }

  /**
   * Pretend the gateway said yes. **Stub builds only.**
   *
   * This is the one route that can grant a subscription without a signed webhook, so it is refused
   * unless the build is explicitly in stub mode — and stub mode is itself refused at boot when
   * `NODE_ENV=production`. Two locks, because one of them is a config value.
   */
  @Post('checkout/simulate')
  @HttpCode(HttpStatus.OK)
  public async simulate(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: SimulateDto,
  ): Promise<{ simulated: true }> {
    if (this.cashfree.mode !== CashfreeMode.Stub) {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: { code: 'NOT_A_STUB_BUILD', user_message: STUB_MODE },
      });
    }

    await this.checkout.simulatePaid(
      Number(request.user.id),
      dto.order_id,
      new Date(),
    );

    return { simulated: true };
  }

  /// The price matrix, so no price is ever hardcoded in the app (docs/11 §2).
  @Get('prices')
  @HttpCode(HttpStatus.OK)
  public prices(): Promise<PriceMatrix> {
    return this.service.prices();
  }
}
