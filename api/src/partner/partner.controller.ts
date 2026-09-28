import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Matches, IsOptional } from 'class-validator';
import { CommissionService, type EarningsView } from './commission.service';
import { ReferralService, type ReferralView } from './referral.service';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

class EarningsQuery {
  /// `YYYY-MM`. Absent means this month. Validated rather than parsed loosely — a period the
  /// server cannot read must not silently become "everything".
  @IsOptional()
  @Matches(/^\d{4}-\d{2}$/)
  period?: string;
}

/**
 * docs/09 §6's partner routes: `GET /coach/earnings?period=`, plus the referral code that feeds it.
 *
 * Mounted under `coach` because that is the path the API spec fixes, even though the module behind
 * it is `partner` — earning and coaching are different relationships, and only one of them involves
 * a client's data.
 */
@ApiTags('Partner')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller({ path: 'coach', version: '1' })
export class PartnerController {
  constructor(
    private readonly commission: CommissionService,
    private readonly referral: ReferralService,
  ) {}

  /**
   * What this partner earned in a month.
   *
   * docs/12 §8: aggregate only. There is deliberately no per-client line — it would tell an
   * affiliate exactly what one person paid, which is neither their business nor anything the
   * client agreed to.
   */
  @Get('earnings')
  @HttpCode(HttpStatus.OK)
  earnings(
    @Request() request: { user: JwtPayloadType },
    @Query() query: EarningsQuery,
  ): Promise<EarningsView> {
    const now = new Date();
    const period = query.period ?? now.toISOString().slice(0, 7);

    return this.commission.earnings(Number(request.user.id), period, now);
  }

  /// The code and link a partner shares. Minted on first ask and stable afterwards — a code that
  /// changed would strand every link already sent.
  @Get('referral')
  @HttpCode(HttpStatus.OK)
  referralCode(
    @Request() request: { user: JwtPayloadType },
  ): Promise<ReferralView> {
    return this.referral.forPartner(Number(request.user.id));
  }
}
