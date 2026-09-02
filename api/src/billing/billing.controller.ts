import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { BillingService, type SubscriptionView } from './billing.service';
import { PRICES } from './tiers';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

@ApiTags('Billing')
@ApiBearerAuth()
@Controller({ path: 'billing', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class BillingController {
  constructor(private readonly service: BillingService) {}

  /// docs/11 §4.
  @Get('entitlements')
  @HttpCode(HttpStatus.OK)
  public entitlements(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<SubscriptionView> {
    return this.service.entitlements(Number(request.user.id));
  }

  /// The price matrix, so no price is ever hardcoded in the app (docs/11 §2).
  @Get('prices')
  @HttpCode(HttpStatus.OK)
  public prices(): typeof PRICES {
    return this.service.prices();
  }
}
