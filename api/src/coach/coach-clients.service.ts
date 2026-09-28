import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { CoachGrantEntity } from './entities/coach-grant.entity';
import { CoachGrantService } from './coach-grant.service';
import {
  ClientSerializer,
  type Access,
  type ClientDetailView,
  type ClientFacts,
  type RosterRow,
} from './client-view.serializer';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { RoleEnum } from '../roles/roles.enum';
import { AuditService } from '../admin/audit.service';
import {
  ClientMetricsService,
  type ClientMetrics,
} from '../clients/client-metrics.service';
import { windowedTrendChange } from '../measurements/measurement-rules';

/// docs/12 §9's coach widgets, as one payload: "active clients, clients at risk (no log ≥3 days),
/// renewals due in 30 days".
export type CoachDashboard = {
  total_clients: number;
  active_clients: number;
  at_risk_clients: number;
  pending_invites: number;
  renewals_due_30d: number;
  /// The at-risk roster, already filtered — docs/12 §9 calls this "the single most valuable widget
  /// you can give a coach", so it arrives ready to render rather than as a flag to filter on.
  needs_attention: RosterRow[];
};

/// How far ahead a renewal counts as "due", per docs/12 §9.
const RENEWAL_HORIZON_DAYS = 30;

/**
 * The coach's own clients — the surface a trainer, nutritionist or doctor works from.
 *
 * **The consent grant is the only thing that opens a door here.** Not the coach's role, not their
 * level, not a client having once been invited. A role only ever narrows what a grant already
 * allowed, and every field decision lives in `ClientSerializer` rather than in this file —
 * docs/10 §6 asks for exactly one place to audit and one place to test.
 */
@Injectable()
export class CoachClientsService {
  constructor(
    @InjectRepository(CoachGrantEntity)
    private readonly grants: Repository<CoachGrantEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
    private readonly grantService: CoachGrantService,
    private readonly metrics: ClientMetricsService,
    private readonly audit: AuditService,
  ) {}

  /**
   * Who this coach is working with, with enough about each to decide who needs attention.
   *
   * **One audit row for the whole read, not one per client.** The roster now carries health-derived
   * fields, so it is a health read and docs/10 §6 wants it recorded — but a row per client would
   * mean a coach with forty clients writes forty rows every time the screen opens, and a trail
   * where every entry is noise is one where the entries that matter cannot be found. The row
   * records the count and the fields, which is what an auditor actually asks.
   */
  async roster(
    coachUserId: number,
    now: Date,
    /// What the audit row calls this read. The check-in queue renders the same rows for a different
    /// screen, and a trail that logged both as `coach/clients` could not tell them apart.
    resource = 'coach/clients',
  ): Promise<RosterRow[]> {
    const rows = await this.rosterRows(coachUserId, now);

    await this.recordRosterRead(coachUserId, resource, rows);
    return rows;
  }

  /// The counts and the at-risk list. Derived from the same rows the roster renders, so the number
  /// on a tile can never disagree with the list under it.
  async dashboard(coachUserId: number, now: Date): Promise<CoachDashboard> {
    const rows = await this.rosterRows(coachUserId, now);

    const [pendingInvites, renewals] = await Promise.all([
      this.pendingInviteCount(coachUserId, now),
      this.renewalsDue(
        rows.map((r) => r.client_user_id),
        now,
      ),
    ]);

    const needsAttention = rows.filter(
      (r) => r.status === 'at_risk' || r.status === 'no_recent_logs',
    );

    await this.recordRosterRead(coachUserId, 'coach/dashboard', rows);

    return {
      total_clients: rows.length,
      active_clients: rows.filter((r) => r.status === 'active').length,
      at_risk_clients: needsAttention.length,
      pending_invites: pendingInvites,
      renewals_due_30d: renewals,
      // Longest since a log first: the coach opened this to find who needs chasing, and sorting by
      // anything else would bury them. Never sorted by weight lost or streak — docs/05 §6 bans
      // ranking people against each other on weight, and a sorted streak column is that ranking.
      needs_attention: needsAttention.sort(
        (a, b) =>
          (b.days_since_last_log ?? 9999) - (a.days_since_last_log ?? 9999),
      ),
    };
  }

  /**
   * One client, filtered to what they allowed and to what this coach's level reaches.
   *
   * Audited whenever a health field actually leaves. A read that carried a name and a goal is not a
   * health read and does not pretend to be one.
   */
  async client(
    coachUserId: number,
    clientUserId: number,
    now: Date,
  ): Promise<ClientDetailView> {
    const access = await this.accessTo(coachUserId, clientUserId, now);

    // No grant is a 404, not a 403. "You are not allowed to see this person" confirms the person
    // exists, and an id space that answers that is a way to enumerate clients.
    if (access.scopes.length === 0) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'CLIENT_NOT_FOUND',
          user_message: 'You do not have access to this client.',
        },
      });
    }

    const grant = await this.grants.findOne({
      where: { coachUserId, clientUserId },
    });
    const facts = await this.factsFor([clientUserId], now, access);
    const view = ClientSerializer.detail(
      { ...facts[0]!, grantExpiresAt: grant?.expiresAt ?? null },
      access,
    );

    if (ClientSerializer.carriedHealthField(view)) {
      await this.audit.record({
        actorUserId: coachUserId,
        actorRole: 'coach',
        action: 'read_health',
        resource: `coach/clients/${clientUserId}`,
        subjectUserId: clientUserId,
        meta: { scopes: access.scopes },
      });
    }

    return view;
  }

  /**
   * One audit row for a whole roster read, and not one per screen refresh.
   *
   * `subjectUserId` is null because this read is not about one person — so the ids go in `meta`,
   * where "who looked at my data" can still find them. That question has to stay answerable:
   * docs/13 gives a person the right to ask it.
   *
   * Collapsed to one row per five minutes. A dashboard that polls would otherwise write a row per
   * poll, and a trail that grows by every refresh is one nobody can read.
   */
  private async recordRosterRead(
    coachUserId: number,
    resource: string,
    rows: readonly RosterRow[],
  ): Promise<void> {
    if (!rows.some((r) => ClientSerializer.carriedHealthField(r))) return;

    const recent = await this.grants.manager.query<{ one: number }[]>(
      `SELECT 1 AS one FROM "audit_log"
       WHERE "actorUserId" = $1 AND "resource" = $2
         AND "createdAt" > now() - interval '5 minutes' LIMIT 1`,
      [coachUserId, resource],
    );
    if (recent.length > 0) return;

    await this.audit.record({
      actorUserId: coachUserId,
      actorRole: 'coach',
      action: 'read_health',
      resource,
      // Ids only. Rule 5 permits a user id in a log and nothing else about the person.
      meta: {
        client_count: rows.length,
        client_user_ids: rows.map((r) => r.client_user_id),
      },
    });
  }

  /// The rows, without the audit row. Shared by the roster and the dashboard so a count and a list
  /// are never computed two different ways.
  private async rosterRows(
    coachUserId: number,
    now: Date,
  ): Promise<RosterRow[]> {
    const live = (
      await this.grants.find({ where: { coachUserId, status: 'active' } })
    ).filter((g) => g.expiresAt > now);

    if (live.length === 0) return [];

    const role = await this.roleOf(coachUserId);

    // Scopes re-checked per client rather than trusted from the grant row: a demotion has to take
    // effect without anyone rewriting grants.
    const scopesById = new Map<number, Access>();
    for (const grant of live) {
      const scopes = await this.grantService.scopesFor(
        coachUserId,
        grant.clientUserId,
        now,
      );
      scopesById.set(grant.clientUserId, { role, scopes });
    }

    const withScopes = live.filter(
      (g) => (scopesById.get(g.clientUserId)?.scopes.length ?? 0) > 0,
    );
    if (withScopes.length === 0) return [];

    // One pass for everybody. Anything the widest access here cannot reach is not fetched at all.
    const widest = widestAccess([...scopesById.values()]);
    const facts = await this.factsFor(
      withScopes.map((g) => g.clientUserId),
      now,
      widest,
    );
    const factsById = new Map(facts.map((f) => [f.userId, f]));

    return withScopes.map((grant) => {
      const access = scopesById.get(grant.clientUserId)!;
      const row = factsById.get(grant.clientUserId)!;
      return ClientSerializer.rosterRow(
        { ...row, grantExpiresAt: grant.expiresAt },
        access,
      );
    });
  }

  /**
   * Everything the database can offer about these clients, in as few queries as it takes.
   *
   * Gated at the FETCH, not only at the serialiser: a field nobody may see is never loaded, so it
   * cannot leak through a logging statement or a debugger. The serialiser is still the thing that
   * decides what leaves — this is the cheaper second lock.
   */
  private async factsFor(
    ids: readonly number[],
    now: Date,
    access: Access,
  ): Promise<ClientFacts[]> {
    const wants = (scope: 'basic' | 'progress' | 'health_conditions') =>
      access.scopes.includes(scope);

    const [profiles, names, tiers, metrics, weightChanges, health] =
      await Promise.all([
        wants('basic') || wants('progress')
          ? this.profiles.find({ where: { userId: In([...ids]) } })
          : Promise.resolve([]),
        this.namesFor(ids),
        wants('basic') ? this.tiersFor(ids) : Promise.resolve(new Map()),
        wants('progress')
          ? this.metrics.forUsers(ids, now)
          : Promise.resolve(new Map<number, ClientMetrics>()),
        wants('progress')
          ? this.weightChangesFor(ids)
          : Promise.resolve(new Map()),
        // Only fetched when the grant carries it. A field nobody may see is never loaded, so it
        // cannot leak through a log line or a debugger — the cheaper second lock behind the
        // serialiser.
        wants('health_conditions')
          ? this.healthFor(ids)
          : Promise.resolve(new Map<number, HealthRow>()),
      ]);

    const profileById = new Map(profiles.map((p) => [p.userId, p]));

    return ids.map((userId) => {
      const profile = profileById.get(userId);

      return {
        userId,
        name: names.get(userId) ?? null,
        ageYears: profile?.ageYears ?? null,
        sexAtBirth: profile?.sexAtBirth ?? null,
        goal: profile?.goal ?? null,
        heightCm: profile?.heightCm ?? null,
        weightKg: profile ? Number(profile.weightKg) : null,
        weightChange30d: weightChanges.get(userId) ?? null,
        tier: tiers.get(userId) ?? null,
        conditions: health.get(userId)?.conditions ?? null,
        allergies: health.get(userId)?.allergies ?? null,
        medications: health.get(userId)?.medications ?? null,
        digestiveSymptoms: health.get(userId)?.digestive_symptoms ?? null,
        injuries: health.get(userId)?.injuries ?? null,
        routine: profile === undefined ? null : routineOf(profile),
        metrics: metrics.get(userId) ?? null,
        grantExpiresAt: null,
      };
    });
  }

  /// docs/10 §3's `progress` scope names a weight SERIES. The roster shows the 30-day trend change
  /// rather than the series itself — the same figure the client sees on their own Progress tab, so
  /// neither side is reading a different number.
  private async weightChangesFor(
    ids: readonly number[],
  ): Promise<Map<number, number>> {
    const rows = await this.measurements.find({
      where: { userId: In([...ids]), kind: 'weight' },
      order: { diaryDate: 'ASC' },
    });

    const byUser = new Map<
      number,
      { value: number; isSuspect: boolean; diaryDate: string }[]
    >();
    for (const row of rows) {
      const points = byUser.get(row.userId) ?? [];
      points.push({
        value: Number(row.value),
        isSuspect: row.isSuspect,
        diaryDate: row.diaryDate,
      });
      byUser.set(row.userId, points);
    }

    const out = new Map<number, number>();
    for (const [userId, points] of byUser) {
      const change = windowedTrendChange(points, 30);
      if (change !== null) out.set(userId, change);
    }
    return out;
  }

  /**
   * The latest health profile for each client.
   *
   * `DISTINCT ON` rather than a per-client query: a profile is versioned and never overwritten
   * (docs/09 §4), so "the current one" is the highest version and one statement answers it for a
   * whole roster.
   *
   * The screening answers are not selected. docs/10 §5.5 puts the eating-disorder screen beyond
   * every role and every grant, and the safest way to honour that is for the query never to ask.
   */
  private async healthFor(
    ids: readonly number[],
  ): Promise<Map<number, HealthRow>> {
    const rows = await this.grants.manager.query<
      ({ userId: number } & HealthRow)[]
    >(
      `SELECT DISTINCT ON ("userId")
              "userId", "conditions", "allergies", "medications",
              "digestiveSymptoms" AS digestive_symptoms, "injuries"
       FROM "health_profile" WHERE "userId" = ANY($1::int[])
       ORDER BY "userId", "version" DESC`,
      [[...ids]],
    );

    return new Map(rows.map((r) => [Number(r.userId), r]));
  }

  private async tiersFor(ids: readonly number[]): Promise<Map<number, string>> {
    const rows = await this.subscriptions.find({
      where: { userId: In([...ids]) },
    });

    // An expired subscription is FREE, not its last paid tier (docs/11 §5). Reading the row's
    // `tier` alone would print PRO for somebody whose period ended in March.
    const now = new Date();
    return new Map(
      rows.map((r) => [
        r.userId,
        r.currentPeriodEnd !== null && r.currentPeriodEnd <= now
          ? 'FREE'
          : r.tier,
      ]),
    );
  }

  private async renewalsDue(
    ids: readonly number[],
    now: Date,
  ): Promise<number> {
    if (ids.length === 0) return 0;

    const horizon = new Date(now);
    horizon.setDate(horizon.getDate() + RENEWAL_HORIZON_DAYS);

    const rows = await this.subscriptions.find({
      where: { userId: In([...ids]) },
    });

    return rows.filter(
      (r) =>
        r.currentPeriodEnd !== null &&
        r.currentPeriodEnd > now &&
        r.currentPeriodEnd <= horizon,
    ).length;
  }

  private async pendingInviteCount(
    coachUserId: number,
    now: Date,
  ): Promise<number> {
    const rows = await this.grants.manager.query<{ count: string }[]>(
      `SELECT COUNT(*)::text AS count FROM "coach_invite"
       WHERE "coachUserId" = $1 AND "status" = 'pending' AND "expiresAt" > $2`,
      [coachUserId, now],
    );

    return Number(rows[0]?.count ?? 0);
  }

  /// A phone-OTP signup never fills `user.firstName` — the name is asked for during onboarding and
  /// lands on the profile. Reading only the user row showed "Client 41" for most of the roster.
  private async namesFor(
    userIds: readonly number[],
  ): Promise<Map<number, string>> {
    const [users, profiles] = await Promise.all([
      this.users.find({ where: { id: In([...userIds]) } }),
      this.profiles.find({ where: { userId: In([...userIds]) } }),
    ]);

    const fromProfile = new Map(
      profiles.map((p) => [p.userId, p.name?.trim() ?? '']),
    );
    const out = new Map<number, string>();

    for (const user of users) {
      const onUser = `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim();
      const name =
        onUser.length > 0 ? onUser : (fromProfile.get(user.id) ?? '');
      if (name.length > 0) out.set(user.id, name);
    }

    return out;
  }

  private async accessTo(
    coachUserId: number,
    clientUserId: number,
    now: Date,
  ): Promise<Access> {
    const [role, scopes] = await Promise.all([
      this.roleOf(coachUserId),
      this.grantService.scopesFor(coachUserId, clientUserId, now),
    ]);

    return { role, scopes };
  }

  private async roleOf(coachUserId: number): Promise<RoleEnum | undefined> {
    const coach = await this.users.findOne({ where: { id: coachUserId } });
    return coach?.role?.id as RoleEnum | undefined;
  }
}

/// The union of what any one client allowed, used to decide which QUERIES to run for a whole
/// roster. Never used to decide what a row shows — that stays per client, in the serialiser.
function widestAccess(all: readonly Access[]): Access {
  const scopes = new Set<string>();
  for (const access of all)
    for (const scope of access.scopes) scopes.add(scope);

  return {
    role: all[0]?.role,
    scopes: [...scopes] as Access['scopes'],
  };
}

type HealthRow = {
  conditions: string[] | null;
  allergies: string[] | null;
  medications: string | null;
  digestive_symptoms: string[] | null;
  injuries: string[] | null;
};

/**
 * The answers a diet plan is actually written from.
 *
 * Kept out of the profile row's shape so the serialiser never has to know which columns exist — it
 * passes the whole bag through under one scope, and adding an onboarding question later reaches a
 * coach without touching the access rules.
 *
 * Nothing medical is in here. Conditions, allergies, medications and injuries live on the health
 * profile behind their own scope.
 */
function routineOf(profile: ProfileEntity): Record<string, unknown> {
  return {
    meal_count: profile.mealCount,
    lifestyle: profile.lifestyle,
    food_preference: profile.foodPreference,
    activity: profile.activity,
    goal_declared: profile.goalDeclared,
    goal_weight_kg: profile.goalWeightKg,
    budget_tier: profile.budgetTier,
    budget_monthly_inr: profile.budgetMonthlyInr,
    food_dislikes: profile.foodDislikes,
    wake_time: profile.wakeTime,
    sleep_time: profile.sleepTime,
    sleep_hours: profile.sleepHours,
    breakfast_time: profile.breakfastTime,
    mid_morning_time: profile.midMorningTime,
    lunch_time: profile.lunchTime,
    evening_snack_time: profile.eveningSnackTime,
    dinner_time: profile.dinnerTime,
    bedtime_snack_time: profile.bedtimeSnackTime,
  };
}
