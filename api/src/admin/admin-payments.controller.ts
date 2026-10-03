import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  ORDER_STATUS,
  type OrderStatus,
} from '../billing/entities/payment-order.entity';
import {
  REFUND_REQUEST_STATUS,
  type RefundRequestStatus,
} from '../billing/entities/refund-request.entity';
import {
  RefundRequestService,
  type RefundRequestView,
} from '../billing/refund-request.service';
import { RefundService, type RefundView } from '../billing/refund.service';
import {
  AdminPaymentsService,
  MAX_PAYMENTS_PAGE,
  type PaymentDetail,
  type PaymentRow,
  type PaymentSummary,
} from './admin-payments.service';
import type { Actor } from './admin-users.service';
import { AuditService } from './audit.service';
import { Permit, PermissionsGuard } from './permissions.guard';
import { withContact } from './permissions';
import { TotpService } from './totp.service';

class PaymentListQuery {
  @IsOptional()
  @IsIn([...ORDER_STATUS])
  status?: OrderStatus;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  user?: number;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsDateString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAYMENTS_PAGE)
  limit?: number;
}

class RefundQuery {
  @IsOptional()
  @IsIn([...REFUND_REQUEST_STATUS])
  status?: RefundRequestStatus;
}

class AdminRefundDto {
  /// Why the money goes back. Stored on the audit row and sent to nobody.
  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reason: string;
}

class RejectDto {
  /// Sent to the person, so it is written for them.
  @IsString()
  @MinLength(3)
  @MaxLength(1000)
  note: string;
}

type StaffRequest = { user: JwtPayloadType };

/// Admin panel plan, Phase B: payments, failed transactions and refunds.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('payments.read')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin', version: '1' })
export class AdminPaymentsController {
  constructor(
    private readonly payments: AdminPaymentsService,
    private readonly refunds: RefundService,
    private readonly requests: RefundRequestService,
    private readonly totp: TotpService,
    private readonly audit: AuditService,
  ) {}

  @Get('payments')
  async list(
    @Query() q: PaymentListQuery,
    @Request() request: StaffRequest,
  ): Promise<{ rows: PaymentRow[]; next_cursor: string | null }> {
    const page = await this.payments.list({
      status: q.status,
      userId: q.user,
      from: q.from ? new Date(q.from) : undefined,
      to: q.to ? new Date(q.to) : undefined,
      cursor: q.cursor ? new Date(q.cursor) : undefined,
      limit: q.limit,
    });
    const role = request.user.role?.id;
    return { ...page, rows: page.rows.map((r) => withContact(role, r)) };
  }

  @Get('payments/summary')
  summary(): Promise<PaymentSummary> {
    return this.payments.summary();
  }

  @Get('payments/:orderId')
  async detail(
    @Param('orderId') orderId: string,
    @Request() request: StaffRequest,
  ): Promise<PaymentDetail> {
    return withContact(
      request.user.role?.id,
      await this.payments.detail(orderId),
    );
  }

  @Permit('refunds.manage')
  @Post('payments/:orderId/remind')
  @HttpCode(HttpStatus.NO_CONTENT)
  remind(
    @Param('orderId') orderId: string,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<void> {
    return this.payments.remind(orderId, actorOf(request, ip));
  }

  /// Money leaves the business: the second factor and a reason, then the same path as self-serve.
  @Permit('refunds.manage')
  @Post('payments/:orderId/refund')
  @HttpCode(HttpStatus.OK)
  async refund(
    @Param('orderId') orderId: string,
    @Body() dto: AdminRefundDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<RefundView> {
    await this.totp.require(Number(request.user.id), code ?? '');
    const done = await this.refunds.refundAsAdmin(
      orderId,
      dto.reason,
      new Date(),
    );
    await this.record(request, ip, 'refund_admin', {
      order_id: orderId,
      refunded_paise: done.refunded_paise,
      reason: dto.reason,
    });
    return done;
  }

  @Get('refunds')
  refundRequests(@Query() q: RefundQuery): Promise<RefundRequestView[]> {
    return this.requests.list(q.status);
  }

  @Permit('refunds.manage')
  @Post('refunds/:id/approve')
  @HttpCode(HttpStatus.OK)
  async approve(
    @Param('id') id: string,
    @Headers('x-totp') code: string | undefined,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<RefundRequestView> {
    await this.totp.require(Number(request.user.id), code ?? '');
    const { request: decided, refund } = await this.requests.approve(
      id,
      Number(request.user.id),
      new Date(),
    );
    await this.record(
      request,
      ip,
      'refund_approve',
      {
        request_id: id,
        order_id: decided.order_id,
        refunded_paise: refund.refunded_paise,
      },
      decided.user_id,
    );
    return decided;
  }

  @Permit('refunds.manage')
  @Post('refunds/:id/reject')
  @HttpCode(HttpStatus.OK)
  async reject(
    @Param('id') id: string,
    @Body() dto: RejectDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<RefundRequestView> {
    const decided = await this.requests.reject(
      id,
      dto.note,
      Number(request.user.id),
      new Date(),
    );
    await this.record(
      request,
      ip,
      'refund_reject',
      {
        request_id: id,
        order_id: decided.order_id,
      },
      decided.user_id,
    );
    return decided;
  }

  private record(
    request: StaffRequest,
    ip: string,
    action: 'refund_admin' | 'refund_approve' | 'refund_reject',
    meta: Record<string, unknown>,
    subjectUserId: number | null = null,
  ): Promise<void> {
    return this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? ''),
      action,
      resource: 'payment_order',
      subjectUserId,
      meta,
      ip,
    });
  }
}

function actorOf(request: StaffRequest, ip: string): Actor {
  return {
    userId: Number(request.user.id),
    roleId: Number(request.user.role?.id),
    ip,
  };
}
