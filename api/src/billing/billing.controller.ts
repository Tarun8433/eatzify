import {
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
import { CashfreeClient } from './cashfree.client';
import { CashfreeMode } from './cashfree.config';
import { PAYMENTS_NOT_OFFERED, STUB_MODE } from './billing-copy';
import { type Tier } from './tiers';
import { type PriceMatrix } from './price.service';
import { PlayBillingService } from './store/play-billing.service';
import { AppStoreBillingService } from './store/app-store-billing.service';
import { InvoiceService, type InvoiceView } from './invoice/invoice.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { cashfreeOffered, platformFrom } from './payment-rails';

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
}

class AppStoreVerifyDto {
  /// StoreKit 2's `jwsRepresentation` of the transaction.
  @IsString()
  @MaxLength(16384)
  signed_transaction: string;
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
    private readonly cashfree: CashfreeClient,
    private readonly play: PlayBillingService,
    private readonly appStore: AppStoreBillingService,
    private readonly invoices: InvoiceService,
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
    await this.play.verify(userId, dto.purchase_token, now);
    return this.subscriptions.state(userId, now);
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
