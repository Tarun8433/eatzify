import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthGuard } from '@nestjs/passport';
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
import { STUB_MODE } from './billing-copy';
import { PRICES, type Tier } from './tiers';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

const DURATIONS = ['1M', '3M', '6M', '9M', '12M'] as const;

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
  ): Promise<SubscriptionView> {
    return this.service.entitlements(Number(request.user.id));
  }

  /// docs/11 §7: charges the difference the quote named, and closes the period it replaces when
  /// the payment lands. A credit that covers the whole price settles without a gateway.
  @Post('upgrade')
  @HttpCode(HttpStatus.OK)
  public upgrade(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: UpgradeDto,
    @Headers('Idempotency-Key') idempotencyKey?: string,
  ): Promise<CheckoutView> {
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
  ): Promise<CheckoutView> {
    return this.checkout.checkout({
      userId: Number(request.user.id),
      tier: dto.tier,
      duration: dto.duration,
      idempotencyKey: idempotencyKey ?? null,
      now: new Date(),
      couponCode: dto.coupon_code ?? null,
    });
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
  public prices(): typeof PRICES {
    return this.service.prices();
  }
}
