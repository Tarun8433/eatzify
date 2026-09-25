import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  Res,
  Param,
  ParseIntPipe,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  ArrayNotEmpty,
  IsArray,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Roles } from '../roles/roles.decorator';
import { RolesGuard } from '../roles/roles.guard';
import { RoleEnum } from '../roles/roles.enum';
import {
  COACH_APPLICATION_STATUS,
  type CoachApplicationStatus,
} from '../coach/entities/coach-application.entity';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  AdminCoachService,
  type ApplicantIdentity,
  type ApplicationQueueRow,
} from './admin-coach.service';
import {
  AdminClientsService,
  type ClientDetail,
  type ClientSummary,
} from './admin-clients.service';
import { AUDIT_REASONS, type AuditReason } from './entities/audit-log.entity';
import {
  AdminMetricsService,
  type AdminOverview,
  type RevenueOverview,
} from './admin-metrics.service';
import { extname } from 'node:path';
import type { Response as ExpressResponse } from 'express';
import { AuditService } from './audit.service';
import {
  AdminAudienceService,
  MAX_SEARCH_ROWS,
  type BroadcastResult,
  type UserSearchRow,
} from './admin-audience.service';
import {
  CONTENT_CLASSES,
  type ContentClass,
} from '../notifications/entities/notification.entity';
import { FoodsService } from '../foods/foods.service';
import {
  FOOD_STATUSES,
  type FoodEntity,
  type FoodStatus,
} from '../foods/entities/food.entity';
import type { AuditLogEntity } from './entities/audit-log.entity';
import {
  TicketsService,
  type TicketRow,
  type TicketThread,
} from '../tickets/tickets.service';
import {
  TICKET_STATUSES,
  type TicketStatus,
} from '../tickets/entities/ticket.entity';
import { TotpService } from './totp.service';
import { CouponsService, type CouponView } from '../billing/coupons.service';

/// docs/09 §9: `POST /admin/users/search { query, filters }`. A POST because a filter may name a
/// health condition, and api rule 6 keeps health data out of query strings.
class UserFiltersDto {
  @IsOptional()
  @IsString()
  tier?: string;

  @IsOptional()
  @IsString()
  goal?: string;

  /// Searching by condition is a health read: the controller demands a reason and writes an audit
  /// row before it answers (docs/10 §4).
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  conditions?: string[];

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  inactive_days?: number;
}

class UserSearchDto {
  @IsOptional()
  @IsString()
  query?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => UserFiltersDto)
  filters?: UserFiltersDto;
}

class SegmentDto extends UserFiltersDto {
  /// Named people, for a send that is not a rule about a group.
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  user_ids?: number[];
}

/// docs/09 §9 + docs/13 §5. `content_class` is part of the message, not a guess made later: the
/// targeting rules turn on it.
class BroadcastDto {
  @IsString()
  title: string;

  @IsString()
  body: string;

  @IsIn([...CONTENT_CLASSES])
  content_class: ContentClass;

  @IsOptional()
  @ValidateNested()
  @Type(() => SegmentDto)
  segment?: SegmentDto;
}

/// docs/09 §9's `POST /admin/foods`. The body is the CSV importer's own column set, validated by
/// the same rules — one definition of "a valid food", whether it arrives in a file or a form.
class FoodDraftDto {
  @IsObject()
  row: Record<string, string>;
}

/// docs/09 §9: `POST /admin/tickets/{id}/reply`.
class TicketReplyDto {
  @IsString()
  body: string;
}

class TicketQueueDto {
  @IsOptional()
  @IsIn([...TICKET_STATUSES])
  status?: TicketStatus;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}

class VerifyCoachDto {
  /// What was actually checked. Non-empty by contract, not by convention — docs/02 FR-8.3 asks for
  /// an explicit "what we verified" record and an empty list makes the unqualified claim doc 00 §8
  /// forbids.
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  verified_attributes: string[];
}

class RejectCoachDto {
  /// Shown to the applicant, so it has to be written for them.
  @IsString()
  reason: string;
}

class QueueQueryDto {
  @IsOptional()
  @IsIn([...COACH_APPLICATION_STATUS])
  status?: CoachApplicationStatus;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}

class AuditQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  actor?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  subject?: number;

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}

/**
 * docs/09 §9. Admin and super_admin only, enforced by the guard on the class rather than per method
 * — a new route added here is protected by default, which is the opposite of how admin surfaces
 * usually leak.
 *
 * What is deliberately NOT here yet: `/admin/users/{id}` (the search returns what it would) and
 * rule-pack activation, which is super_admin's alone and lives with the rule packs rather than here.
 */
@ApiTags('Admin')
@ApiBearerAuth()
@Roles(RoleEnum.admin, RoleEnum.super_admin)
@UseGuards(AuthGuard('jwt'), RolesGuard)
class CreateCouponDto {
  @IsString()
  code: string;

  @IsInt()
  @Min(1)
  @Max(90)
  percent_off: number;

  @IsInt()
  @Min(1)
  max_uses: number;

  @IsOptional()
  @IsString()
  expires_at?: string | null;
}

@Controller({ path: 'admin', version: '1' })
export class AdminController {
  constructor(
    private readonly metrics: AdminMetricsService,
    private readonly coaches: AdminCoachService,
    private readonly clients: AdminClientsService,
    private readonly audience: AdminAudienceService,
    private readonly foods: FoodsService,
    private readonly tickets: TicketsService,
    private readonly totp: TotpService,
    private readonly audit: AuditService,
    private readonly couponsService: CouponsService,
  ) {}

  /**
   * docs/09 §9: find somebody. Names, goals and a masked number — never a diary.
   *
   * Searching BY a health condition is itself a health read (docs/10 §4), so that one shape of this
   * request needs an `X-Reason` and writes an audit row. A search by name does not, and demanding a
   * reason for every lookup is how reasons stop meaning anything.
   */
  @Post('users/search')
  @HttpCode(HttpStatus.OK)
  async searchUsers(
    @Body() dto: UserSearchDto,
    @Headers('x-reason') reason: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<UserSearchRow[]> {
    const readsHealth = AdminAudienceService.readsHealth(dto.filters);
    if (readsHealth && !AUDIT_REASONS.includes(reason as AuditReason)) {
      throw new BadRequestException({
        error: {
          code: 'REASON_REQUIRED',
          user_message: `An X-Reason header is required: ${AUDIT_REASONS.join(', ')}.`,
        },
      });
    }

    const rows = await this.audience.search(dto.query, dto.filters, new Date());

    if (readsHealth) {
      await this.audit.record({
        actorUserId: Number(request.user.id),
        actorRole: String(request.user.role?.id ?? RoleEnum.admin),
        action: 'read_health',
        resource: 'admin/users/search',
        reason: reason as AuditReason,
        ip,
        // Ids and counts only (rule 5).
        meta: {
          matched: rows.length,
          capped_at: MAX_SEARCH_ROWS,
          conditions: dto.filters?.conditions ?? [],
        },
      });
    }

    return rows;
  }

  /// docs/09 §9: the review queue, a step at a time.
  @Get('foods')
  foodsByStatus(@Query('status') status?: string): Promise<FoodEntity[]> {
    const wanted = (FOOD_STATUSES as readonly string[]).includes(status ?? '')
      ? (status as FoodStatus)
      : 'draft';

    return this.foods.byStatus(wanted);
  }

  /// docs/09 §9: one food, typed rather than imported. A DRAFT whatever the body says — nothing
  /// reaches a plan because somebody pressed save.
  @Post('foods')
  @HttpCode(HttpStatus.CREATED)
  createFood(@Body() dto: FoodDraftDto): Promise<FoodEntity> {
    return this.foods.createDraft(dto.row);
  }

  /// docs/09 §9: `POST /admin/foods/{id}/review`.
  @Post('foods/:id/review')
  @HttpCode(HttpStatus.OK)
  reviewFood(
    @Param('id') id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<FoodEntity> {
    return this.foods.review(id, Number(request.user.id), new Date());
  }

  /// docs/09 §9: `POST /admin/foods/{id}/publish`. Only from `reviewed`.
  @Post('foods/:id/publish')
  @HttpCode(HttpStatus.OK)
  publishFood(
    @Param('id') id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<FoodEntity> {
    return this.foods.publish(id, Number(request.user.id), new Date());
  }

  /// Out of circulation, not deleted: the row is in somebody's diary (docs/08 §4).
  @Post('foods/:id/retire')
  @HttpCode(HttpStatus.OK)
  retireFood(
    @Param('id') id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<FoodEntity> {
    return this.foods.retire(id, Number(request.user.id), new Date());
  }

  /**
   * docs/09 §9: `GET /admin/tickets`. With no status it is the work — everything still waiting on
   * support, oldest first. Subjects and ids; the conversation itself needs the route below.
   */
  @Get('tickets')
  ticketQueue(@Query() query: TicketQueueDto): Promise<TicketRow[]> {
    return this.tickets.queue(query.status, query.limit);
  }

  /**
   * One conversation, in full.
   *
   * docs/10 §4 makes support access ticket-scoped and audited: reading somebody's ticket is a
   * `read_pii` — they wrote it in their own words, and those words are routinely a phone number and
   * an order id. No reason header, for the same reason the applicant reveal needs none: `docs/10`
   * §4's reason requirement is about health fields, and support that cannot read the ticket it is
   * answering cannot answer it.
   */
  @Get('tickets/:id')
  async ticket(
    @Param('id') id: string,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<TicketThread> {
    const thread = await this.tickets.thread(id, {
      userId: Number(request.user.id),
      isSupport: true,
    });

    await this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? RoleEnum.admin),
      action: 'read_pii',
      resource: `ticket/${id}`,
      subjectUserId: thread.user_id,
      reason: 'support_ticket',
      ip,
    });

    return thread;
  }

  /// docs/09 §9: `POST /admin/tickets/{id}/reply`. The person gets a notification (D-223).
  @Post('tickets/:id/reply')
  @HttpCode(HttpStatus.OK)
  replyToTicket(
    @Param('id') id: string,
    @Body() dto: TicketReplyDto,
    @Request() request: { user: JwtPayloadType },
  ): Promise<TicketRow> {
    return this.tickets.reply(
      id,
      { userId: Number(request.user.id), isSupport: true },
      dto.body,
    );
  }

  /// docs/03 §5: resolved, and reopenable for seven days if it was not.
  @Post('tickets/:id/resolve')
  @HttpCode(HttpStatus.OK)
  resolveTicket(@Param('id') id: string): Promise<TicketRow> {
    return this.tickets.resolve(id);
  }

  /// Final. docs/13 §6's two-year retention runs from here.
  @Post('tickets/:id/close')
  @HttpCode(HttpStatus.OK)
  closeTicket(@Param('id') id: string): Promise<TicketRow> {
    return this.tickets.close(id);
  }

  /**
   * docs/09 §9: `POST /admin/notifications`.
   *
   * docs/13 §5's rule is enforced in the service: a segment that names a health condition is
   * allowed only for a clinical message. A send that used one is audited whatever it said.
   */
  @Post('notifications')
  @HttpCode(HttpStatus.OK)
  async broadcast(
    @Body() dto: BroadcastDto,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<BroadcastResult> {
    const result = await this.audience.broadcast(
      {
        title: dto.title,
        body: dto.body,
        contentClass: dto.content_class,
        segment: dto.segment,
      },
      new Date(),
    );

    if ((dto.segment?.conditions?.length ?? 0) > 0) {
      await this.audit.record({
        actorUserId: Number(request.user.id),
        actorRole: String(request.user.role?.id ?? RoleEnum.admin),
        action: 'read_health',
        resource: 'admin/notifications',
        reason: 'safety_review',
        ip,
        meta: {
          sent: result.sent,
          content_class: result.content_class,
          conditions: dto.segment?.conditions ?? [],
        },
      });
    }

    return result;
  }

  /// Names and goals, no diary. Not a health read, so no reason header is required to browse.
  @Get('clients')
  clientList(): Promise<ClientSummary[]> {
    return this.clients.list();
  }

  /**
   * One client's diary, plan and weights — health data, every field of it.
   *
   * docs/10 §4: "admin reads of any health field require a `reason` header value from a closed list
   * which lands in the audit log. Un-reasoned reads are rejected." Enforced here rather than
   * documented: without `X-Reason` this 400s before it touches the diary.
   */
  @Get('clients/:userId')
  async clientDetail(
    @Param('userId', ParseIntPipe) userId: number,
    @Headers('x-reason') reason: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<ClientDetail> {
    if (!reason || !AUDIT_REASONS.includes(reason as AuditReason)) {
      throw new BadRequestException({
        error: {
          code: 'REASON_REQUIRED',
          user_message: `An X-Reason header is required: ${AUDIT_REASONS.join(', ')}.`,
        },
      });
    }

    const detail = await this.clients.detail(userId);

    await this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? RoleEnum.admin),
      action: 'read_health',
      resource: `client/${userId}`,
      subjectUserId: userId,
      reason: reason as AuditReason,
      ip,
    });

    return detail;
  }

  /// Counts only, so there is nothing here to audit a read of.
  @Get('metrics/overview')
  overview(): Promise<AdminOverview> {
    return this.metrics.overview();
  }

  /// D-236. Sums only — no row here names a buyer.
  @Get('metrics/revenue')
  revenue(): Promise<RevenueOverview> {
    return this.metrics.revenue();
  }

  /// D-236 — the offers. Creating one changes what people pay, so it sits behind the second
  /// factor like the other dangerous actions (D-229); reading the list does not.
  @Get('coupons')
  coupons(): Promise<CouponView[]> {
    return this.couponsService.list();
  }

  @Post('coupons')
  async createCoupon(
    @Headers('x-totp') code: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Body() body: CreateCouponDto,
  ): Promise<CouponView> {
    await this.totp.require(Number(request.user.id), code ?? '');
    return this.couponsService.create(body);
  }

  /// Deactivation, never deletion — a code that ever ran stays visible with its usage.
  @Post('coupons/:code/deactivate')
  async deactivateCoupon(
    @Headers('x-totp') code: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Param('code') coupon: string,
  ): Promise<CouponView> {
    await this.totp.require(Number(request.user.id), code ?? '');
    return this.couponsService.deactivate(coupon);
  }

  /// The review queue. Masked by default (docs/13 §4) — user ids, never names or phones.
  @Get('coaches/applications')
  applications(@Query() query: QueueQueryDto): Promise<ApplicationQueueRow[]> {
    return this.coaches.queue(query.status, query.limit);
  }

  /**
   * Reveal one applicant's identity and everything they declared.
   *
   * docs/13 §4's other half: the queue masks, this reveals, and the reveal writes a `read_pii` audit
   * row. No reason header — that is docs/10 §4's requirement for HEALTH fields, and an applicant's
   * own name is not one. An admin who cannot see who they are verifying cannot verify anybody.
   */
  @Get('coaches/:userId/applicant')
  async applicant(
    @Param('userId', ParseIntPipe) userId: number,
    @Headers('x-totp') code: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<ApplicantIdentity> {
    // D-229: the full phone number is one of the three things worth a second factor. The queue
    // above needs none — it is masked, and a reviewer works from it all day.
    await this.totp.require(Number(request.user.id), code ?? '');

    return this.coaches.identity(userId, {
      userId: Number(request.user.id),
      role: String(request.user.role?.id ?? RoleEnum.admin),
      ip,
    });
  }

  /**
   * Stream one of an applicant's documents.
   *
   * Streamed, not linked. docs/13 §4 asks for signed URLs of five minutes or less; the local driver
   * cannot sign anything, and the boilerplate's own `GET /files/:path` route has no guard on it at
   * all. Serving the bytes through this endpoint means the only key is the reviewer's token, every
   * open writes an audit row, and there is no URL to forward.
   */
  @Get('coaches/:userId/documents/:kind')
  async document(
    @Param('userId', ParseIntPipe) userId: number,
    @Param('kind') kind: string,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
    @Res() response: ExpressResponse,
  ): Promise<void> {
    if (kind !== 'id' && kind !== 'qualification') {
      throw new BadRequestException({
        error: { code: 'UNKNOWN_DOCUMENT', user_message: 'No such document.' },
      });
    }

    const doc = await this.coaches.document(userId, kind, {
      userId: Number(request.user.id),
      role: String(request.user.role?.id ?? RoleEnum.admin),
      ip,
    });

    // `inline` so a reviewer sees the document rather than downloading it, and `no-store` so a
    // verification document never lands in a disk cache or a proxy.
    response.setHeader('Cache-Control', 'no-store, private');
    response.setHeader(
      'Content-Disposition',
      `inline; filename="${kind}-${userId}${extname(doc.filename)}"`,
    );
    response.sendFile(doc.absolutePath);
  }

  @Post('coaches/:userId/verify')
  verify(
    @Param('userId', ParseIntPipe) userId: number,
    @Body() dto: VerifyCoachDto,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<ApplicationQueueRow> {
    return this.coaches.verify(userId, dto.verified_attributes, {
      userId: Number(request.user.id),
      role: String(request.user.role?.id ?? RoleEnum.admin),
      ip,
    });
  }

  @Post('coaches/:userId/reject')
  reject(
    @Param('userId', ParseIntPipe) userId: number,
    @Body() dto: RejectCoachDto,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<ApplicationQueueRow> {
    return this.coaches.reject(userId, dto.reason, {
      userId: Number(request.user.id),
      role: String(request.user.role?.id ?? RoleEnum.admin),
      ip,
    });
  }

  /// docs/09 §9: `GET /admin/audit?actor=&subject=&from=&to=`.
  @Get('audit')
  auditLog(@Query() query: AuditQueryDto): Promise<AuditLogEntity[]> {
    return this.audit.search({
      actorUserId: query.actor,
      subjectUserId: query.subject,
      from: query.from ? new Date(query.from) : undefined,
      to: query.to ? new Date(query.to) : undefined,
      limit: query.limit,
    });
  }
}
