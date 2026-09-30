import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  Param,
  ParseIntPipe,
  ParseUUIDPipe,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { Roles } from '../roles/roles.decorator';
import { RolesGuard } from '../roles/roles.guard';
import { RoleEnum } from '../roles/roles.enum';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { TotpService } from './totp.service';
import { AuditService } from './audit.service';
import type { AuditAction } from './entities/audit-log.entity';
import {
  PayoutService,
  payoutView,
  type PayoutRunReport,
  type PayoutView,
  type ReconciliationReport,
} from '../partner/payout.service';
import { KycService, type KycReveal } from '../partner/kyc.service';
import {
  PAYOUT_STATUS,
  type PayoutStatus,
  type TdsRateEntity,
} from '../partner/entities/payout.entity';

class RunDto {
  @Matches(/^\d{4}-\d{2}$/)
  period: string;
}

class StatusQuery {
  @IsOptional()
  @IsIn(PAYOUT_STATUS)
  status?: PayoutStatus;
}

class PaidDto {
  /// The bank's transfer reference (NEFT/IMPS/RTGS UTR).
  @Matches(/^[A-Za-z0-9]{8,32}$/)
  utr: string;
}

class KycReviewDto {
  @IsIn(['verified', 'rejected'])
  status: 'verified' | 'rejected';
}

class TdsRateDto {
  @IsInt()
  @Min(0)
  @Max(10_000)
  rate_bps: number;

  @IsDateString()
  effective_from: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

type Req = { user: JwtPayloadType };

/**
 * docs/12 §5, payments plan Phase 6: the payout desk. Every action that decides money needs the
 * second factor and writes an audit row; reading the queue needs neither.
 */
@ApiTags('Admin')
@ApiBearerAuth()
@Roles(RoleEnum.admin, RoleEnum.super_admin)
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller({ path: 'admin', version: '1' })
export class AdminPayoutsController {
  constructor(
    private readonly payouts: PayoutService,
    private readonly kyc: KycService,
    private readonly totp: TotpService,
    private readonly audit: AuditService,
  ) {}

  @Get('payouts')
  list(@Query() query: StatusQuery): Promise<PayoutView[]> {
    return this.payouts.listByStatus(query.status ?? 'pending_approval');
  }

  /// Runs the month by hand — the scheduler does the same on the 1st. Prepares, never pays.
  @Post('payouts/run')
  @HttpCode(HttpStatus.OK)
  run(@Body() dto: RunDto): Promise<PayoutRunReport> {
    return this.payouts.prepare(dto.period, new Date());
  }

  @Get('payouts/reconciliation')
  reconcile(): Promise<ReconciliationReport> {
    return this.payouts.reconcile();
  }

  @Post('payouts/:id/paid')
  @HttpCode(HttpStatus.OK)
  async paid(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: PaidDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: Req,
    @Ip() ip: string,
  ): Promise<PayoutView> {
    const adminId = await this.secondFactor(request, code);
    const payout = await this.payouts.markPaid(
      id,
      dto.utr,
      adminId,
      new Date(),
    );
    await this.record(
      request,
      ip,
      'payout_paid',
      `payout:${id}`,
      payout.partnerUserId,
    );
    return payoutView(payout);
  }

  @Post('payouts/:id/cancel')
  @HttpCode(HttpStatus.NO_CONTENT)
  async cancel(
    @Param('id', ParseUUIDPipe) id: string,
    @Headers('x-totp') code: string | undefined,
    @Request() request: Req,
    @Ip() ip: string,
  ): Promise<void> {
    await this.secondFactor(request, code);
    const payout = await this.payouts.cancel(id);
    await this.record(
      request,
      ip,
      'payout_cancel',
      `payout:${id}`,
      payout.partnerUserId,
    );
  }

  /// D-255: the partner's full payout details, to send the transfer. Second factor and a
  /// `read_pii` audit row, the same as revealing an applicant's identity (D-229).
  @Get('partners/:userId/kyc')
  async revealKyc(
    @Param('userId', ParseIntPipe) userId: number,
    @Headers('x-totp') code: string | undefined,
    @Request() request: Req,
    @Ip() ip: string,
  ): Promise<KycReveal> {
    await this.secondFactor(request, code);
    const details = await this.kyc.reveal(userId);
    await this.record(request, ip, 'read_pii', `partner_kyc:${userId}`, userId);
    return details;
  }

  /// Verified after checking the details against the partner's documents; rejected sends the app
  /// back to asking for them.
  @Post('partners/:userId/kyc/review')
  @HttpCode(HttpStatus.NO_CONTENT)
  async reviewKyc(
    @Param('userId', ParseIntPipe) userId: number,
    @Body() dto: KycReviewDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: Req,
    @Ip() ip: string,
  ): Promise<void> {
    await this.secondFactor(request, code);
    await this.kyc.review(userId, dto.status, new Date());
    // The decision only; never the digits (api rule 5).
    await this.record(
      request,
      ip,
      'kyc_update',
      `partner_kyc:${userId}`,
      userId,
      {
        status: dto.status,
      },
    );
  }

  @Get('tds-rates')
  tdsRates(): Promise<TdsRateEntity[]> {
    return this.payouts.listTdsRates();
  }

  /// docs/12 §5: the rate the CA confirmed, from a date on. Added, never edited.
  @Post('tds-rates')
  async addTdsRate(
    @Body() dto: TdsRateDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: Req,
    @Ip() ip: string,
  ): Promise<TdsRateEntity> {
    await this.secondFactor(request, code);
    const row = await this.payouts.addTdsRate({
      rateBps: dto.rate_bps,
      effectiveFrom: new Date(dto.effective_from),
      note: dto.note ?? null,
    });
    await this.record(request, ip, 'tds_rate_add', `tds_rate:${row.id}`, null, {
      rate_bps: dto.rate_bps,
      effective_from: dto.effective_from,
    });
    return row;
  }

  private async secondFactor(
    request: Req,
    code: string | undefined,
  ): Promise<number> {
    const adminId = Number(request.user.id);
    await this.totp.require(adminId, code ?? '');
    return adminId;
  }

  private record(
    request: Req,
    ip: string,
    action: AuditAction,
    resource: string,
    subjectUserId: number | null,
    meta?: Record<string, unknown>,
  ): Promise<void> {
    return this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? RoleEnum.admin),
      action,
      resource,
      subjectUserId,
      meta,
      ip,
    });
  }
}
