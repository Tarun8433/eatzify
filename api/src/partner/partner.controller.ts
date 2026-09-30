import {
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  Param,
  ParseUUIDPipe,
  HttpStatus,
  Put,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Length, Matches, IsOptional } from 'class-validator';
import { CommissionService, type EarningsView } from './commission.service';
import { ReferralService, type ReferralView } from './referral.service';
import { PayoutService, type PayoutView } from './payout.service';
import { KycService, type KycView } from './kyc.service';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

class EarningsQuery {
  /// `YYYY-MM`. Absent means this month. Validated rather than parsed loosely — a period the
  /// server cannot read must not silently become "everything".
  @IsOptional()
  @Matches(/^\d{4}-\d{2}$/)
  period?: string;
}

/// D-255: what a partner sends when a payout is due. Formats checked here; the full PAN and
/// account number are sealed before they are stored.
class KycDto {
  @Length(2, 100)
  holder_name: string;

  @Matches(/^[A-Z]{5}[0-9]{4}[A-Z]$/)
  pan: string;

  @Matches(/^[0-9]{9,18}$/)
  account_number: string;

  @Matches(/^[A-Z]{4}0[A-Z0-9]{6}$/)
  ifsc: string;

  @IsOptional()
  @Matches(/^[0-9]{2}[A-Z0-9]{13}$/)
  gstin?: string;
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
    private readonly payouts: PayoutService,
    private readonly kyc: KycService,
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

  /// docs/12 §5: this partner's payouts, waiting or paid. Scoped to the caller — never a user id
  /// from the request.
  @Get('payouts')
  payoutList(
    @Request() request: { user: JwtPayloadType },
  ): Promise<PayoutView[]> {
    return this.payouts.listForPartner(Number(request.user.id));
  }

  /// D-255: whether payout details are needed yet, and what is on file (last four digits only).
  @Get('payouts/kyc')
  kycStatus(@Request() request: { user: JwtPayloadType }): Promise<KycView> {
    return this.kyc.viewFor(Number(request.user.id), new Date());
  }

  @Put('payouts/kyc')
  kycSubmit(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: KycDto,
  ): Promise<KycView> {
    return this.kyc.submit(
      Number(request.user.id),
      {
        holderName: dto.holder_name.trim(),
        pan: dto.pan,
        accountNumber: dto.account_number,
        ifsc: dto.ifsc,
        gstin: dto.gstin ?? null,
      },
      new Date(),
    );
  }

  /// docs/12 §5: "Every payout generates a downloadable statement". CSV, the caller's own only.
  @Get('payouts/:id/statement')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @Header(
    'Content-Disposition',
    'attachment; filename="eatzify-payout-statement.csv"',
  )
  statement(
    @Request() request: { user: JwtPayloadType },
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<string> {
    return this.payouts.statementCsv(Number(request.user.id), id);
  }
}
