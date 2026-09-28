import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { CoachGrantService } from './coach-grant.service';
import { RoleEnum } from '../roles/roles.enum';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AuditService } from '../admin/audit.service';
import {
  ClientMetricsService,
  type ClientMetrics,
} from '../clients/client-metrics.service';
import { LogsService } from '../logs/logs.service';
import { diaryDateFor } from '../plans/diary-date';
import {
  foldStepsAdded,
  trendChange,
  windowedTrendChange,
} from '../measurements/measurement-rules';

/// How far back a coach's charts go. Ninety days is a quarter — long enough to show whether
/// something is working, short enough that the payload stays one screen's worth of points.
const SERIES_DAYS = 90;

/**
 * What a client has logged, for the coach they shared it with.
 *
 * docs/10 §3's `progress` scope, in full: "weight series, adherence %, steps, streaks". Those four
 * were already granted and simply were not being rendered — a coach whose client had shared
 * everything saw five profile fields.
 */
export type ClientProgressView = {
  client_user_id: string;
  /// One entry per kind the client has recorded. Kinds they never logged are absent rather than
  /// present and empty — an empty chart reads as a flat line, which is a claim.
  series: Record<string, { date: string; value: number }[]>;
  /// The moving-average trend, the same figure the client sees on their own Progress tab. Neither
  /// side should be reading a different number for the same question.
  weight_change_total: number | null;
  weight_change_30d: number | null;
  /**
   * What they ate against what the plan asked for, averaged over the days they logged.
   *
   * **This is the number a nutritionist actually reads.** `adherence_pct` is logging FREQUENCY —
   * docs/02 FR-4.2 defines it that way and it is honest about what it counts — but somebody can
   * log a pizza every day and score 100 % on it. These four say whether the food matched the plan.
   */
  avg_kcal: number | null;
  avg_protein_g: number | null;
  target_kcal: number | null;
  target_protein_g: number | null;
  adherence_pct: number | null;
  days_logged: number;
  window_days: number;
  streak_days: number;
  last_logged_date: string | null;
};

/// One day of the client's diary. Only for a coaching partner — docs/10 §2 puts food logs at
/// `📊 adherence %` for coach_l2 and `✅` for coach_l3.
export type ClientDiaryView = {
  client_user_id: string;
  day: unknown;
};

/**
 * The coach-facing read of a client's own logs.
 *
 * Every method here asks the same two questions first: does a live grant carry the scope, and does
 * the coach's level reach it. Neither alone is enough — docs/10 §1: "the level does not grant
 * access. The consent grant does. The level caps what a grant may contain."
 */
@Injectable()
export class CoachProgressService {
  constructor(
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly grants: CoachGrantService,
    private readonly metrics: ClientMetricsService,
    private readonly logs: LogsService,
    private readonly audit: AuditService,
  ) {}

  /**
   * Weight, steps, water and the rest of what this client measures.
   *
   * Needs `progress` and a verified coach. docs/10 §2 puts weight history at ❌ for coach_l1, so an
   * affiliate reaches none of this however the grant was written.
   */
  async progress(
    coachUserId: number,
    clientUserId: number,
    now: Date,
  ): Promise<ClientProgressView> {
    await this.require(coachUserId, clientUserId, now, 'progress', [
      RoleEnum.coach_l2,
      RoleEnum.coach_l3,
    ]);

    const since = new Date(now);
    since.setDate(since.getDate() - SERIES_DAYS);
    const oldest = diaryDateFor(since);

    const rows = await this.measurements.find({
      where: { userId: clientUserId },
      order: { diaryDate: 'ASC' },
    });

    // The coach sees the same step count the client does (D-221).
    const recent = foldStepsAdded(rows.filter((r) => r.diaryDate >= oldest));
    const series: ClientProgressView['series'] = {};

    for (const row of recent) {
      // Suspect rows are kept out of a coach's chart for the same reason they are kept out of the
      // client's: a mistyped 7 kg is not a data point, and a coach acting on one would be acting
      // on a typo.
      if (row.isSuspect) continue;

      (series[row.kind] ??= []).push({
        date: row.diaryDate,
        value: Number(row.value),
      });
    }

    const weights = rows
      .filter((r) => r.kind === 'weight')
      .map((r) => ({
        value: Number(r.value),
        isSuspect: r.isSuspect,
        diaryDate: r.diaryDate,
      }));

    const metrics = (await this.metrics.forUsers([clientUserId], now)).get(
      clientUserId,
    );

    await this.recordRead(coachUserId, clientUserId, 'progress');

    return {
      client_user_id: String(clientUserId),
      series,
      weight_change_total: trendChange(weights),
      weight_change_30d: windowedTrendChange(weights, 30),
      ...summaryOf(metrics),
    };
  }

  /**
   * One day of what the client actually ate.
   *
   * **A verified coach, with the client's `progress` grant.** docs/10 §2 originally put food logs
   * at `📊 adherence %` for coach_l2 and the logs themselves at coach_l3; D-204 moved that line,
   * because a nutritionist who cannot see what somebody ate cannot do the job they were hired for.
   *
   * The consent grant still decides. A client who did not share `progress` shares no diary, and
   * revoking takes it back on the next read.
   */
  async diary(
    coachUserId: number,
    clientUserId: number,
    /// Undefined means today. NOT an empty string — `LogsService.day` defaults with `??`, and `''`
    /// slips past it straight into a `date` column.
    diaryDate: string | undefined,
    now: Date,
  ): Promise<ClientDiaryView> {
    await this.require(coachUserId, clientUserId, now, 'progress', [
      RoleEnum.coach_l2,
      RoleEnum.coach_l3,
    ]);

    const day = await this.logs.day(
      clientUserId,
      // Belt as well as braces: whatever a caller hands over, an empty string means "today" here
      // rather than reaching the database as a date.
      diaryDate === undefined || diaryDate.length === 0 ? undefined : diaryDate,
    );
    await this.recordRead(coachUserId, clientUserId, 'diary');

    return { client_user_id: String(clientUserId), day };
  }

  /**
   * The grant carries the scope AND the level reaches it, or the client is simply not found.
   *
   * A 403 would confirm the person exists and that the coach merely lacks a level — which turns
   * the id space into a way to learn who is a client of whom.
   */
  private async require(
    coachUserId: number,
    clientUserId: number,
    now: Date,
    scope: 'progress' | 'plan_view',
    levels: readonly RoleEnum[],
  ): Promise<void> {
    const [scopes, coach] = await Promise.all([
      this.grants.scopesFor(coachUserId, clientUserId, now),
      this.users.findOne({ where: { id: coachUserId } }),
    ]);

    const role = coach?.role?.id as RoleEnum | undefined;
    const allowed =
      scopes.includes(scope) && role !== undefined && levels.includes(role);

    if (allowed) return;

    throw new NotFoundException({
      status: HttpStatus.NOT_FOUND,
      error: {
        code: 'CLIENT_NOT_FOUND',
        user_message: 'You do not have access to this client.',
      },
    });
  }

  /// docs/10 §6. One row per read, naming the person it was about — unlike the roster, this read IS
  /// about one person and the audit row says so.
  private async recordRead(
    coachUserId: number,
    clientUserId: number,
    view: string,
  ): Promise<void> {
    await this.audit.record({
      actorUserId: coachUserId,
      actorRole: 'coach',
      action: 'read_health',
      resource: `coach/clients/${clientUserId}/${view}`,
      subjectUserId: clientUserId,
      meta: { view },
    });
  }
}

/// Null where the answer is unknown, never zero — the same rule the roster follows. Somebody who
/// has never logged has no adherence figure, and 0 % would be a verdict.
function summaryOf(metrics: ClientMetrics | undefined) {
  return {
    avg_kcal: metrics?.avgKcal ?? null,
    avg_protein_g: metrics?.avgProteinG ?? null,
    target_kcal: metrics?.targetKcal ?? null,
    target_protein_g: metrics?.targetProteinG ?? null,
    adherence_pct: metrics?.adherencePct ?? null,
    days_logged: metrics?.daysLogged ?? 0,
    window_days: metrics?.windowDays ?? 0,
    streak_days: metrics?.streakDays ?? 0,
    last_logged_date: metrics?.lastLoggedDate ?? null,
  };
}
