import { Injectable } from '@nestjs/common';
import { CouponsService, type CouponView } from '../billing/coupons.service';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, type SelectQueryBuilder } from 'typeorm';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { CoachGrantEntity } from '../coach/entities/coach-grant.entity';
import { CoachInviteEntity } from '../coach/entities/coach-invite.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { RoleEnum } from '../roles/roles.enum';

/// A label per role id, so the response never makes the caller know that 5 means `coach_l3`.
const ROLE_LABEL: Record<number, string> = {
  [RoleEnum.admin]: 'admin',
  [RoleEnum.user]: 'user',
  [RoleEnum.coach_l1]: 'coach_l1',
  [RoleEnum.coach_l2]: 'coach_l2',
  [RoleEnum.coach_l3]: 'coach_l3',
  [RoleEnum.partner_org]: 'partner_org',
  [RoleEnum.support]: 'support',
  [RoleEnum.super_admin]: 'super_admin',
};

export interface AdminOverview {
  users: {
    total: number;
    by_role: Record<string, number>;
    /// The plain members — everyone who is not staff and not a partner. The number the question
    /// "how many normal users" is actually asking for.
    normal: number;
  };
  coach_applications: {
    total: number;
    by_status: Record<string, number>;
    /// Self-declared at application time. `unknown` is every row written before the column existed.
    by_discipline: Record<string, number>;
    /// What a human actually confirmed, which is not the same question — the gap between this and
    /// `by_discipline` is the claim nobody has checked yet.
    verified_by_attribute: Record<string, number>;
    /// The queue. docs/12 §6 level 2 means "someone looked", so an unreviewed pile is the one
    /// number on this page with a person waiting at the other end of it.
    awaiting_review: number;
    oldest_awaiting_review_days: number | null;
  };
  invites: {
    total: number;
    by_status: Record<string, number>;
    /// accepted / (total - pending). Pending invites are not failures yet, so they are excluded
    /// rather than counted against the rate.
    acceptance_rate: number | null;
  };
  grants: {
    active: number;
    by_scope: Record<string, number>;
    /// The most sensitive scope there is (docs/10 §5.3). Worth its own line so it can be watched
    /// rather than found.
    active_health_conditions: number;
  };
  subscriptions: {
    by_tier: Record<string, number>;
    by_status: Record<string, number>;
  };
}

/// D-236 — what the business earned and which plans earn it. Money is integer paise as STRINGS
/// (api rule 3: bigint sums do not fit a JS number and must not become floats on the wire).
export interface RevenueOverview {
  /// Rolling windows over `paidAt`, kept money only (a refunded order leaves its window).
  totals: {
    week_paise: string;
    month_paise: string;
    year_paise: string;
    all_time_paise: string;
  };
  refunded_all_time_paise: string;
  /// Every plan cell ever sold, best-seller first.
  by_plan: {
    tier: string;
    duration: string;
    sold: number;
    gross_paise: string;
  }[];
  coupons: CouponView[];
}

/**
 * `GET /admin/metrics/overview` (docs/09 §9).
 *
 * Counts only — no row here identifies anybody. That is what lets this endpoint answer "how many"
 * without every call writing a `read_pii` audit row, and it is why the queue below returns a COUNT
 * and a waiting time rather than a list of names.
 *
 * docs/08 §10: the rollup excludes `is_demo` (D-230). The flag lives on `user`, so every count here
 * drops the rows belonging to a demo account — which is the rule doc 08 wrote against exactly this
 * failure: a dashboard showing ₹1,24,560 of revenue against four real users.
 */
@Injectable()
export class AdminMetricsService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(CoachInviteEntity)
    private readonly invites: Repository<CoachInviteEntity>,
    @InjectRepository(CoachGrantEntity)
    private readonly grants: Repository<CoachGrantEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    private readonly coupons: CouponsService,
  ) {}

  /// `GET /admin/metrics/revenue` (D-236). Same demo exclusion as every other rollup (docs/08
  /// §10): an order by a demo account is not revenue, whatever it says it paid.
  async revenue(now = new Date()): Promise<RevenueOverview> {
    const paid = () =>
      this.orders
        .createQueryBuilder('o')
        .innerJoin('user', 'u', 'u.id = o."userId" AND u."isDemo" = false')
        .where("o.status = 'paid'");

    const sumSince = async (since: Date | null): Promise<string> => {
      const q = paid().select('COALESCE(SUM(o."amountPaise"), 0)', 'sum');
      if (since !== null) q.andWhere('o."paidAt" >= :since', { since });
      const row = await q.getRawOne<{ sum: string }>();
      return row?.sum ?? '0';
    };

    const days = (n: number): Date => new Date(now.getTime() - n * 86_400_000);

    const refundedRow = await this.orders
      .createQueryBuilder('o')
      .innerJoin('user', 'u', 'u.id = o."userId" AND u."isDemo" = false')
      .where("o.status = 'refunded'")
      .select('COALESCE(SUM(o."amountPaise"), 0)', 'sum')
      .getRawOne<{ sum: string }>();

    const planRows = await paid()
      .select('o.tier', 'tier')
      .addSelect('o.duration', 'duration')
      .addSelect('COUNT(*)', 'sold')
      .addSelect('SUM(o."amountPaise")', 'gross')
      .groupBy('o.tier')
      .addGroupBy('o.duration')
      .orderBy('sold', 'DESC')
      .addOrderBy('gross', 'DESC')
      .getRawMany<{
        tier: string;
        duration: string;
        sold: string;
        gross: string;
      }>();

    return {
      totals: {
        week_paise: await sumSince(days(7)),
        month_paise: await sumSince(days(30)),
        year_paise: await sumSince(days(365)),
        all_time_paise: await sumSince(null),
      },
      refunded_all_time_paise: refundedRow?.sum ?? '0',
      by_plan: planRows.map((r) => ({
        tier: r.tier,
        duration: r.duration,
        sold: Number(r.sold),
        gross_paise: r.gross,
      })),
      coupons: await this.coupons.list(),
    };
  }

  async overview(): Promise<AdminOverview> {
    // Read once and pass down. A seeded box has a handful of these and production has none, so a
    // list of ids is cheaper than a join on every one of the queries below.
    const demo = await this.demoUserIds();

    const [users, applications, invites, grants, subscriptions] =
      await Promise.all([
        this.userCounts(),
        this.applicationCounts(demo),
        this.inviteCounts(demo),
        this.grantCounts(demo),
        this.subscriptionCounts(demo),
      ]);

    return { users, ...applications, ...invites, ...grants, ...subscriptions };
  }

  /// Whose rows do not count (docs/08 §10).
  private async demoUserIds(): Promise<number[]> {
    const rows = await this.users.find({
      where: { isDemo: true },
      select: ['id'],
    });
    return rows.map((row) => row.id);
  }

  private async userCounts(): Promise<AdminOverview['users']> {
    // `withDeleted` is off by default, so a soft-deleted user is already excluded — a deleted
    // account should not inflate the headline number.
    const rows = await this.users
      .createQueryBuilder('u')
      .select('u.roleId', 'roleId')
      .addSelect('COUNT(*)', 'count')
      .where('u.isDemo = false')
      .groupBy('u.roleId')
      .getRawMany<{ roleId: number | null; count: string }>();

    const byRole: Record<string, number> = {};
    let total = 0;
    let normal = 0;

    for (const row of rows) {
      const count = Number(row.count);
      total += count;
      // A user row with no role is a boilerplate edge, not a category. It counts as a member,
      // because that is what it behaves as everywhere else in the app.
      const id = row.roleId ?? RoleEnum.user;
      const label = ROLE_LABEL[id] ?? `role_${id}`;
      byRole[label] = (byRole[label] ?? 0) + count;
      if (id === RoleEnum.user) normal += count;
    }

    return { total, by_role: byRole, normal };
  }

  private async applicationCounts(
    demo: number[],
  ): Promise<Pick<AdminOverview, 'coach_applications'>> {
    const byStatus = await this.groupCount(
      this.applications,
      'status',
      'none',
      {
        columns: ['userId'],
        ids: demo,
      },
    );
    const byDiscipline = await this.groupCount(
      this.applications,
      'discipline',
      'unknown',
      { columns: ['userId'], ids: demo },
    );

    // One row per application, so a person claiming two things is counted once per attribute —
    // which is the honest shape: "we confirmed a degree AND a licence" is two facts about one file.
    const verifiedRows = await this.exclude(
      this.applications
        .createQueryBuilder('a')
        .select('a.verifiedAttributes', 'attrs')
        .where('a.status = :status', { status: 'verified' }),
      'a',
      ['userId'],
      demo,
    ).getRawMany<{ attrs: string[] | null }>();

    const verifiedByAttribute: Record<string, number> = {};
    for (const row of verifiedRows) {
      for (const attr of row.attrs ?? []) {
        verifiedByAttribute[attr] = (verifiedByAttribute[attr] ?? 0) + 1;
      }
    }

    const oldest = await this.exclude(
      this.applications
        .createQueryBuilder('a')
        .select('MIN(a.submittedAt)', 'oldest')
        .where('a.status = :status', { status: 'submitted' }),
      'a',
      ['userId'],
      demo,
    ).getRawOne<{ oldest: Date | null }>();

    const awaiting = byStatus.submitted ?? 0;

    return {
      coach_applications: {
        total: Object.values(byStatus).reduce((a, b) => a + b, 0),
        by_status: byStatus,
        by_discipline: byDiscipline,
        verified_by_attribute: verifiedByAttribute,
        awaiting_review: awaiting,
        oldest_awaiting_review_days: this.daysSince(oldest?.oldest ?? null),
      },
    };
  }

  private async inviteCounts(
    demo: number[],
  ): Promise<Pick<AdminOverview, 'invites'>> {
    const byStatus = await this.groupCount(this.invites, 'status', 'none', {
      columns: ['coachUserId'],
      ids: demo,
    });
    const total = Object.values(byStatus).reduce((a, b) => a + b, 0);

    // Everything that has had its chance to be answered. An invite still pending has not failed.
    const settled = total - (byStatus.pending ?? 0);

    return {
      invites: {
        total,
        by_status: byStatus,
        acceptance_rate:
          settled === 0
            ? null
            : Math.round(((byStatus.accepted ?? 0) / settled) * 100) / 100,
      },
    };
  }

  private async grantCounts(
    demo: number[],
  ): Promise<Pick<AdminOverview, 'grants'>> {
    // Active means status active AND not expired. A row whose `expiresAt` has passed is dead
    // whatever the status column says — docs/10 §3 stores the expiry precisely so it can lapse
    // without anybody running a job.
    const active = this.exclude(
      this.grants
        .createQueryBuilder('g')
        .where('g.status = :status', { status: 'active' })
        .andWhere('g.expiresAt > now()'),
      'g',
      ['clientUserId', 'coachUserId'],
      demo,
    );

    const rows = await active
      .clone()
      .select('g.scopes', 'scopes')
      .getRawMany<{ scopes: string[] | null }>();

    const byScope: Record<string, number> = {};
    for (const row of rows) {
      for (const scope of row.scopes ?? []) {
        byScope[scope] = (byScope[scope] ?? 0) + 1;
      }
    }

    return {
      grants: {
        active: rows.length,
        by_scope: byScope,
        active_health_conditions: byScope.health_conditions ?? 0,
      },
    };
  }

  private async subscriptionCounts(
    demo: number[],
  ): Promise<Pick<AdminOverview, 'subscriptions'>> {
    const not = { columns: ['userId'], ids: demo };

    return {
      subscriptions: {
        by_tier: await this.groupCount(this.subscriptions, 'tier', 'none', not),
        by_status: await this.groupCount(
          this.subscriptions,
          'status',
          'none',
          not,
        ),
      },
    };
  }

  /// Drops the rows whose user is a demo account. No demo accounts, no clause — which is every
  /// production box.
  private exclude<T extends object>(
    query: SelectQueryBuilder<T>,
    alias: string,
    columns: string[],
    ids: number[],
  ): SelectQueryBuilder<T> {
    if (ids.length === 0) return query;

    for (const [index, column] of columns.entries()) {
      query.andWhere(`${alias}.${column} NOT IN (:...demo${index})`, {
        [`demo${index}`]: ids,
      });
    }
    return query;
  }

  /// GROUP BY one column into `{ value: count }`, with a name for the null bucket.
  private async groupCount<T extends object>(
    repo: Repository<T>,
    column: string,
    nullLabel = 'none',
    not?: { columns: string[]; ids: number[] },
  ): Promise<Record<string, number>> {
    const query = repo
      .createQueryBuilder('t')
      .select(`t.${column}`, 'value')
      .addSelect('COUNT(*)', 'count')
      .groupBy(`t.${column}`);

    const rows = await this.exclude(
      query,
      't',
      not?.columns ?? [],
      not?.ids ?? [],
    ).getRawMany<{ value: string | null; count: string }>();

    const out: Record<string, number> = {};
    for (const row of rows) {
      out[row.value ?? nullLabel] = Number(row.count);
    }
    return out;
  }

  private daysSince(date: Date | null): number | null {
    if (!date) return null;
    const ms = Date.now() - new Date(date).getTime();
    return Math.max(0, Math.floor(ms / 86_400_000));
  }
}
