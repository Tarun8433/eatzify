import {
  ConflictException,
  HttpStatus,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import { EmailOtpService } from '../auth/email-otp/email-otp.service';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { RoleEnum } from '../roles/roles.enum';
import { SessionEntity } from '../session/infrastructure/persistence/relational/entities/session.entity';
import { StatusEnum } from '../statuses/statuses.enum';
import { TicketEntity } from '../tickets/entities/ticket.entity';
import { UserAccessService } from '../users/user-access.service';
import {
  UserBlockEntity,
  type BlockReason,
} from '../users/infrastructure/persistence/relational/entities/user-block.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { maskPhone } from './admin-clients.service';
import { AuditService } from './audit.service';
import type { AuditReason } from './entities/audit-log.entity';
import { STAFF_ROLES } from './permissions';

export type AccountState = 'active' | 'unverified' | 'blocked';
export type BlockDuration = '24h' | '7d' | '30d' | 'permanent';

const DURATION_MS: Record<Exclude<BlockDuration, 'permanent'>, number> = {
  '24h': 86_400_000,
  '7d': 7 * 86_400_000,
  '30d': 30 * 86_400_000,
};

export const MAX_PAGE = 100;

export type Actor = { userId: number; roleId: number; ip?: string | null };

export type AdminUserRow = {
  user_id: number;
  name: string;
  /// The full address. The controller removes it for a role without `users.reveal` (D-261).
  email?: string | null;
  email_masked: string | null;
  phone_masked: string | null;
  role: string;
  state: AccountState;
  registered_at: string;
  last_login_at: string | null;
};

export type AdminUserDetail = AdminUserRow & {
  provider: string;
  is_demo: boolean;
  subscription: { tier: string; status: string; ends_at: string | null } | null;
  blocks: {
    reason: string;
    note: string | null;
    blocked_by: number;
    blocked_at: string;
    until: string | null;
    lifted_at: string | null;
    lifted_by: number | null;
  }[];
  sessions: { started_at: string }[];
  payments: {
    order_id: string;
    amount_paise: string;
    status: string;
    tier: string;
    duration: string;
    created_at: string;
  }[];
  tickets: {
    id: string;
    subject: string;
    status: string;
    last_message_at: string;
  }[];
};

/// `a…@gmail.com`: the first letter and the domain — enough to tell two accounts apart in a list,
/// not enough to write to (docs/13 §4).
export function maskEmail(email: string | null): string | null {
  if (!email) return null;
  const at = email.indexOf('@');
  if (at < 1) return '••••';
  return `${email[0]}…${email.slice(at)}`;
}

export function stateOf(user: Pick<UserEntity, 'status'>): AccountState {
  const id = Number(user.status?.id);
  if (id === StatusEnum.blocked) return 'blocked';
  if (id === StatusEnum.inactive) return 'unverified';
  return 'active';
}

const STATE_STATUS: Record<AccountState, StatusEnum> = {
  active: StatusEnum.active,
  unverified: StatusEnum.inactive,
  blocked: StatusEnum.blocked,
};

/// Admin panel plan, Phase A: the people behind the accounts — list, profile, and the actions an
/// admin takes on them. Every action writes an audit row; contact details are masked everywhere
/// except the audited reveal.
@Injectable()
export class AdminUsersService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(UserBlockEntity)
    private readonly blocks: Repository<UserBlockEntity>,
    @InjectRepository(SessionEntity)
    private readonly sessions: Repository<SessionEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(TicketEntity)
    private readonly tickets: Repository<TicketEntity>,
    private readonly access: UserAccessService,
    private readonly audit: AuditService,
    // Auth lives behind a module cycle (auth → billing → partner → coach → admin), so its two
    // services are looked up when needed rather than injected.
    private readonly moduleRef: ModuleRef,
  ) {}

  /// Newest first, keyset-paged on id (no offset paging on a list that grows).
  async list(filter: {
    state?: AccountState;
    from?: Date;
    to?: Date;
    cursor?: number;
    limit?: number;
  }): Promise<{ rows: AdminUserRow[]; next_cursor: number | null }> {
    const limit = Math.min(Math.max(filter.limit ?? 50, 1), MAX_PAGE);
    const q = this.users
      .createQueryBuilder('u')
      .leftJoinAndSelect('u.role', 'role')
      .leftJoinAndSelect('u.status', 'status')
      .orderBy('u.id', 'DESC')
      .take(limit + 1);
    if (filter.state) {
      q.andWhere('status.id = :status', {
        status: STATE_STATUS[filter.state],
      });
    }
    if (filter.from) q.andWhere('u.createdAt >= :from', { from: filter.from });
    if (filter.to) q.andWhere('u.createdAt <= :to', { to: filter.to });
    if (filter.cursor) q.andWhere('u.id < :cursor', { cursor: filter.cursor });

    const found = await q.getMany();
    const page = found.slice(0, limit);
    return {
      rows: page.map((u) => this.row(u)),
      next_cursor: found.length > limit ? page[page.length - 1].id : null,
    };
  }

  /// docs/09 §9 `GET /admin/users/{id}`: everything an admin needs to help someone, contact masked.
  async detail(userId: number): Promise<AdminUserDetail> {
    const user = await this.find(userId);
    const [blocks, sessions, payments, sub, tickets] = await Promise.all([
      this.blocks.find({ where: { userId }, order: { blockedAt: 'DESC' } }),
      this.sessions.find({
        where: { user: { id: userId } },
        order: { createdAt: 'DESC' },
        take: 10,
      }),
      this.orders.find({
        where: { userId },
        order: { createdAt: 'DESC' },
        take: 20,
      }),
      this.subscriptions.findOne({
        where: { userId },
        order: { startsAt: 'DESC' },
      }),
      this.tickets.find({
        where: { userId },
        order: { lastMessageAt: 'DESC' },
        take: 10,
      }),
    ]);

    return {
      ...this.row(user),
      provider: user.provider,
      is_demo: user.isDemo,
      subscription: sub
        ? {
            tier: sub.tier,
            status: sub.status,
            ends_at: sub.currentPeriodEnd?.toISOString() ?? null,
          }
        : null,
      blocks: blocks.map((b) => ({
        reason: b.reason,
        note: b.note,
        blocked_by: b.blockedBy,
        blocked_at: b.blockedAt.toISOString(),
        until: b.until?.toISOString() ?? null,
        lifted_at: b.liftedAt?.toISOString() ?? null,
        lifted_by: b.liftedBy,
      })),
      sessions: sessions.map((s) => ({
        started_at: s.createdAt.toISOString(),
      })),
      payments: payments.map((o) => ({
        order_id: o.cashfreeOrderId,
        amount_paise: String(o.amountPaise),
        status: o.status,
        tier: o.tier,
        duration: o.duration,
        created_at: o.createdAt.toISOString(),
      })),
      tickets: tickets.map((t) => ({
        id: t.id,
        subject: t.subject,
        status: t.status,
        last_message_at: t.lastMessageAt.toISOString(),
      })),
    };
  }

  /// The full email and phone, for one person, with a reason — the audited half of docs/13 §4.
  async reveal(
    userId: number,
    reason: AuditReason,
    actor: Actor,
  ): Promise<{ email: string | null; phone: string | null }> {
    const user = await this.find(userId);
    await this.record(
      actor,
      'read_pii',
      userId,
      { fields: ['email', 'phone'] },
      reason,
    );
    return { email: user.email, phone: user.phone };
  }

  async block(
    userId: number,
    input: { reason: BlockReason; duration: BlockDuration; note?: string },
    actor: Actor,
    now = new Date(),
  ): Promise<AdminUserDetail> {
    const user = await this.find(userId);
    this.refuseOnStaffOrSelf(user, actor);
    if (await this.access.openBlock(userId, now)) {
      throw this.conflict(
        'ALREADY_BLOCKED',
        'This account is already blocked.',
      );
    }

    const until =
      input.duration === 'permanent'
        ? null
        : new Date(now.getTime() + DURATION_MS[input.duration]);
    await this.blocks.save(
      this.blocks.create({
        userId,
        reason: input.reason,
        note: input.note?.trim() || null,
        blockedBy: actor.userId,
        blockedAt: now,
        until,
      }),
    );
    const before = stateOf(user);
    await this.setStatus(userId, StatusEnum.blocked);
    // Signed out everywhere: the next token refresh finds no session (access tokens last 15 min).
    await this.endSessions(userId);

    await this.record(actor, 'user_block', userId, {
      before: { state: before },
      after: { state: 'blocked', until: until?.toISOString() ?? null },
      block_reason: input.reason,
      duration: input.duration,
    });
    return this.detail(userId);
  }

  async unblock(
    userId: number,
    actor: Actor,
    now = new Date(),
  ): Promise<AdminUserDetail> {
    await this.find(userId);
    const open = await this.blocks.findOne({
      where: { userId, liftedAt: IsNull() },
    });
    if (!open) {
      throw this.conflict('NOT_BLOCKED', 'This account is not blocked.');
    }
    await this.access.lift(open, actor.userId, now);
    await this.record(actor, 'user_unblock', userId, {
      before: { state: 'blocked' },
      after: { state: 'active' },
    });
    return this.detail(userId);
  }

  /// Names only. Email, phone, role and status each have their own audited path.
  async update(
    userId: number,
    input: { first_name?: string; last_name?: string },
    actor: Actor,
  ): Promise<AdminUserDetail> {
    const user = await this.find(userId);
    const changes: Partial<UserEntity> = {};
    if (input.first_name !== undefined)
      changes.firstName = input.first_name.trim() || null;
    if (input.last_name !== undefined)
      changes.lastName = input.last_name.trim() || null;
    const fields = Object.keys(changes).filter(
      (k) => changes[k as keyof UserEntity] !== user[k as keyof UserEntity],
    );
    if (fields.length) {
      await this.users.update({ id: userId }, changes);
      // Which fields, never their values: a name is PII and this is a log (api rule 5).
      await this.record(actor, 'user_update', userId, { fields });
    }
    return this.detail(userId);
  }

  /// Soft delete (the row keeps `deletedAt`, so payments and audit still resolve). Super admin.
  async remove(userId: number, actor: Actor): Promise<void> {
    const user = await this.find(userId);
    this.refuseOnStaffOrSelf(user, actor);
    await this.endSessions(userId);
    await this.users.softDelete({ id: userId });
    await this.record(actor, 'user_delete', userId, {
      before: { state: stateOf(user) },
      after: { state: 'deleted' },
    });
  }

  async sendPasswordReset(userId: number, actor: Actor): Promise<void> {
    const user = await this.find(userId);
    if (!user.email) {
      throw this.unprocessable(
        'NO_EMAIL',
        'This account has no email address.',
      );
    }
    await this.moduleRef
      .get(AuthService, { strict: false })
      .forgotPassword(user.email);
    await this.record(actor, 'password_reset_sent', userId, {});
  }

  async resendVerification(userId: number, actor: Actor): Promise<void> {
    const user = await this.find(userId);
    if (stateOf(user) !== 'unverified' || !user.email) {
      throw this.unprocessable(
        'ALREADY_VERIFIED',
        'This account has already confirmed its email.',
      );
    }
    await this.moduleRef
      .get(EmailOtpService, { strict: false })
      .issue(userId, user.email);
    await this.record(actor, 'verification_resent', userId, {});
  }

  /// Accounts waiting on their emailed code (D-250), oldest first — the ones most likely stuck.
  async unverified(limit = 50): Promise<AdminUserRow[]> {
    const rows = await this.users.find({
      where: { status: { id: StatusEnum.inactive } },
      relations: { role: true, status: true },
      order: { createdAt: 'ASC' },
      take: Math.min(limit, MAX_PAGE),
    });
    return rows.map((u) => this.row(u));
  }

  async counts(): Promise<Record<AccountState, number>> {
    const rows = await this.users
      .createQueryBuilder('u')
      .select('u."statusId"', 'status')
      .addSelect('COUNT(*)', 'n')
      .where('u."isDemo" = false')
      .groupBy('u."statusId"')
      .getRawMany<{ status: number; n: string }>();
    const by = new Map(rows.map((r) => [Number(r.status), Number(r.n)]));
    return {
      active: by.get(StatusEnum.active) ?? 0,
      unverified: by.get(StatusEnum.inactive) ?? 0,
      blocked: by.get(StatusEnum.blocked) ?? 0,
    };
  }

  private row(u: UserEntity): AdminUserRow {
    return {
      user_id: u.id,
      name: [u.firstName, u.lastName].filter(Boolean).join(' '),
      email: u.email,
      email_masked: maskEmail(u.email),
      phone_masked: maskPhone(u.phone),
      role: u.role?.name ?? String(u.role?.id ?? ''),
      state: stateOf(u),
      registered_at: u.createdAt.toISOString(),
      last_login_at: u.lastLoginAt?.toISOString() ?? null,
    };
  }

  private async find(userId: number): Promise<UserEntity> {
    const user = await this.users.findOne({
      where: { id: userId },
      relations: { role: true, status: true },
    });
    if (!user) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'USER_NOT_FOUND', user_message: 'No such user.' },
      });
    }
    return user;
  }

  /// Staff accounts change through the Admins & Roles page, not moderation, and nobody blocks or
  /// deletes themselves.
  private refuseOnStaffOrSelf(user: UserEntity, actor: Actor): void {
    if (user.id === actor.userId) {
      throw this.conflict(
        'SELF_ACTION',
        'You cannot do this to your own account.',
      );
    }
    if (STAFF_ROLES.includes(Number(user.role?.id) as RoleEnum)) {
      throw this.conflict(
        'STAFF_ACCOUNT',
        'Change a staff account from Admins & Roles first.',
      );
    }
  }

  private async endSessions(userId: number): Promise<void> {
    await this.sessions
      .createQueryBuilder()
      .delete()
      .where('"userId" = :userId', { userId })
      .execute();
  }

  private async setStatus(userId: number, status: StatusEnum): Promise<void> {
    await this.users
      .createQueryBuilder()
      .update()
      .set({ status: { id: status } })
      .where('id = :id', { id: userId })
      .execute();
  }

  private record(
    actor: Actor,
    action: Parameters<AuditService['record']>[0]['action'],
    subjectUserId: number,
    meta: Record<string, unknown>,
    reason: AuditReason | null = null,
  ): Promise<void> {
    return this.audit.record({
      actorUserId: actor.userId,
      actorRole: String(actor.roleId),
      action,
      resource: 'user',
      subjectUserId,
      meta,
      reason,
      ip: actor.ip ?? null,
    });
  }

  private conflict(code: string, message: string): ConflictException {
    return new ConflictException({
      status: HttpStatus.CONFLICT,
      error: { code, user_message: message },
    });
  }

  private unprocessable(code: string, message: string) {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: message },
    });
  }
}
