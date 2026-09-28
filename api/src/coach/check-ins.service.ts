import {
  HttpStatus,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, QueryFailedError, Repository } from 'typeorm';
import { CheckInEntity } from './entities/check-in.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { CoachClientsService } from './coach-clients.service';
import { NotificationsService } from '../notifications/notifications.service';
import { diaryDateFor } from '../plans/diary-date';
import type { RosterRow } from './client-view.serializer';
import {
  alertsFor,
  byRisk,
  daysBetweenDates,
  isOverdue,
  weekOf,
  type AlertKind,
  type CheckInStatus,
} from './check-in-rules';

export type CheckInView = {
  id: string;
  client_user_id: number;
  name: string;
  due_on: string;
  status: CheckInStatus;
  completed_at: string | null;
  notes: string | null;
  actions: string[];
  /// What the coach opened the queue to see: who has gone quiet.
  days_since_last_log: number | null;
  adherence_pct: number | null;
};

export type AlertView = {
  client_user_id: number;
  name: string;
  kinds: AlertKind[];
  days_since_last_log: number | null;
  weight_change_30d: number | null;
  plan_ends_in_days: number | null;
};

/// The most a coach may write on one review. Long enough for a real note, short enough that the
/// field is a note rather than a document nobody reads.
export const MAX_NOTE_LENGTH = 2000;
export const MAX_ACTIONS = 10;
export const MAX_ACTION_LENGTH = 200;

/**
 * docs/02 FR-5.2 and FR-5.3, over docs/09 §6's two endpoints.
 *
 * The queue is GENERATED as it is read: every live client gets this week's row the first time the
 * tab is opened, and anything still `due` from an earlier week becomes `missed`. No cron — a
 * weekly job that silently stops leaves a coach with an empty queue and no reason to suspect one.
 *
 * Everything the queue shows comes from the roster, which is where the grant and the coach's level
 * are already enforced (docs/10). A client whose grant has lapsed simply is not in it.
 */
@Injectable()
export class CheckInsService {
  constructor(
    @InjectRepository(CheckInEntity)
    private readonly checkIns: Repository<CheckInEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly clients: CoachClientsService,
    private readonly notifications: NotificationsService,
  ) {}

  /// [status] filters what comes back; docs/09 §6 uses `?status=due`.
  async queue(
    coachUserId: number,
    now: Date,
    status?: CheckInStatus,
  ): Promise<CheckInView[]> {
    const roster = await this.clients.roster(
      coachUserId,
      now,
      'coach/checkins',
    );
    if (roster.length === 0) return [];

    const thisWeek = weekOf(diaryDateFor(now));
    await this.settleOverdue(coachUserId, thisWeek);
    await this.openThisWeek(coachUserId, roster, thisWeek);

    const rows = await this.checkIns.find({
      where: {
        coachUserId,
        clientUserId: In(roster.map((r) => r.client_user_id)),
        ...(status ? { status } : {}),
      },
    });

    const byClient = new Map(roster.map((r) => [r.client_user_id, r]));
    const views = rows.map((row) =>
      this.toView(row, byClient.get(row.clientUserId)),
    );

    return byRisk(views);
  }

  /// docs/09 §6: `POST /coach/checkins/{id}/complete { notes, actions[] }`.
  ///
  /// The client is told it happened — a review they never hear about is one they cannot act on —
  /// and the message says nothing about how they are doing (docs/05 §6).
  async complete(
    coachUserId: number,
    id: string,
    input: { notes?: string; actions?: string[] },
    now: Date,
  ): Promise<CheckInView> {
    const row = await this.checkIns.findOne({ where: { id, coachUserId } });
    if (!row) throw new NotFoundException();

    const notes = (input.notes ?? '').trim();
    const actions = (input.actions ?? [])
      .map((a) => a.trim())
      .filter((a) => a.length > 0);

    if (notes.length > MAX_NOTE_LENGTH || actions.length > MAX_ACTIONS) {
      throw this.refuse();
    }
    if (actions.some((a) => a.length > MAX_ACTION_LENGTH)) throw this.refuse();

    row.status = 'completed';
    row.completedAt = now;
    row.notes = notes.length > 0 ? notes : null;
    row.actions = actions.length > 0 ? actions : null;
    await this.checkIns.save(row);

    await this.notifications.notify({
      userId: row.clientUserId,
      kind: 'checkin_completed',
      contentClass: 'service',
      title: 'Your coach has reviewed your week',
      body:
        actions.length > 0
          ? `They suggested: ${actions.join('; ')}`
          : 'Open the app to see what they said.',
      data: { check_in_id: row.id },
      dedupeKey: `checkin:${row.id}`,
    });

    // The roster gives the name and the figures the view carries; one read, already access-checked.
    const roster = await this.clients.roster(
      coachUserId,
      now,
      'coach/checkins',
    );
    return this.toView(
      row,
      roster.find((r) => r.client_user_id === row.clientUserId),
    );
  }

  /// docs/02 FR-5.3: no log ≥ 3 days, off trend, plan expiring, check-in missed.
  async alerts(coachUserId: number, now: Date): Promise<AlertView[]> {
    const roster = await this.clients.roster(coachUserId, now, 'coach/alerts');
    if (roster.length === 0) return [];

    const ids = roster.map((r) => r.client_user_id);
    const [missed, endings] = await Promise.all([
      this.checkIns.find({
        where: { coachUserId, clientUserId: In(ids), status: 'missed' },
      }),
      this.planEndings(ids, now),
    ]);

    const missedBy = new Set(missed.map((row) => row.clientUserId));
    const today = diaryDateFor(now);

    return roster
      .map((client) => {
        const endsOn = endings.get(client.client_user_id) ?? null;
        const endsInDays =
          endsOn === null ? null : daysBetweenDates(today, endsOn);
        const kinds = alertsFor({
          daysSinceLastLog: client.days_since_last_log ?? null,
          goal: client.goal ?? null,
          weightChange30d: client.weight_change_30d ?? null,
          planEndsInDays: endsInDays,
          missedCheckIn: missedBy.has(client.client_user_id),
        });

        return {
          client_user_id: client.client_user_id,
          name: client.name,
          kinds,
          days_since_last_log: client.days_since_last_log ?? null,
          weight_change_30d: client.weight_change_30d ?? null,
          plan_ends_in_days: endsInDays,
        };
      })
      .filter((alert) => alert.kinds.length > 0);
  }

  /// Anything still `due` from a week that has passed is missed. Said once, in the database, so
  /// two screens cannot disagree about it.
  private async settleOverdue(
    coachUserId: number,
    thisWeek: string,
  ): Promise<void> {
    const open = await this.checkIns.find({
      where: { coachUserId, status: 'due' },
    });
    const late = open.filter((row) => isOverdue(row.dueOn, thisWeek));

    for (const row of late) {
      row.status = 'missed';
      await this.checkIns.save(row);
    }
  }

  /// This week's row for every live client, created on first read.
  private async openThisWeek(
    coachUserId: number,
    roster: readonly RosterRow[],
    thisWeek: string,
  ): Promise<void> {
    const existing = await this.checkIns.find({
      where: {
        coachUserId,
        clientUserId: In(roster.map((r) => r.client_user_id)),
        dueOn: thisWeek,
      },
    });
    const have = new Set(existing.map((row) => row.clientUserId));

    for (const client of roster) {
      if (have.has(client.client_user_id)) continue;
      try {
        await this.checkIns.save(
          this.checkIns.create({
            coachUserId,
            clientUserId: client.client_user_id,
            dueOn: thisWeek,
            status: 'due',
          }),
        );
      } catch (error) {
        // Two tabs opened at once: the unique index refused the second, which is the point of it.
        if (!this.isDuplicate(error)) throw error;
      }
    }
  }

  /// When each client's plan runs out, for the expiring alert. Absent means nothing to expire.
  private async planEndings(
    ids: readonly number[],
    now: Date,
  ): Promise<Map<number, string>> {
    const rows = await this.subscriptions.find({
      where: {
        userId: In([...ids]),
        status: In(['trialing', 'active', 'grace']),
      },
    });

    const out = new Map<number, string>();
    for (const row of rows) {
      if (!row.currentPeriodEnd || row.currentPeriodEnd <= now) continue;
      out.set(row.userId, diaryDateFor(row.currentPeriodEnd));
    }
    return out;
  }

  private toView(row: CheckInEntity, client?: RosterRow): CheckInView {
    return {
      id: row.id,
      client_user_id: row.clientUserId,
      // A client who has since revoked their grant leaves a row with no name to put on it. The
      // queue filters those out; this keeps the view honest rather than inventing one.
      name: client?.name ?? '',
      due_on: row.dueOn,
      status: row.status,
      completed_at: row.completedAt?.toISOString() ?? null,
      notes: row.notes,
      actions: row.actions ?? [],
      days_since_last_log: client?.days_since_last_log ?? null,
      adherence_pct: client?.adherence_pct ?? null,
    };
  }

  private isDuplicate(error: unknown): boolean {
    return (
      error instanceof QueryFailedError &&
      (error.driverError as { code?: string })?.code === '23505'
    );
  }

  private refuse(): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: {
        code: 'CHECK_IN_TOO_LONG',
        user_message: 'Please shorten the note before saving it.',
      },
    });
  }
}
