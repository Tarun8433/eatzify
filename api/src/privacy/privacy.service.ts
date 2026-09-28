import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, LessThan, Repository } from 'typeorm';
import {
  PrivacyRequestEntity,
  type PrivacyRequestKind,
} from './entities/privacy-request.entity';
import {
  erasureDueAt,
  exportExpiresAt,
  RETENTION_DAYS,
  retentionCutoff,
} from './privacy-rules';
import { ConsentEntity } from '../profile/entities/consent.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { PlanEntity } from '../plans/entities/plan.entity';
import { ExerciseEntity } from '../gym/entities/exercise.entity';
import { GymProfileEntity } from '../gym/entities/gym-profile.entity';
import { GymRoutineEntity } from '../gym/entities/gym-routine.entity';
import { GymWorkoutEntity } from '../gym/entities/gym-workout.entity';
import { NotificationsService } from '../notifications/notifications.service';

/**
 * docs/13 §3's itemised consents, minus the two that are not rows in this table.
 *
 * "Account & service" is necessary — there is no version of this product that does not identify
 * you, so offering a toggle would be a lie. "Coach sharing" is docs/10 §3's grant: per coach,
 * scoped and expiring, which a boolean cannot express, and it already has its own screen.
 */
export const CONSENT_TYPES = [
  'health_data_storage',
  'plan_generation',
  'marketing',
] as const;
export type ConsentType = (typeof CONSENT_TYPES)[number];

/// Withdrawing this one stops plan generation (docs/13 §3).
export const HEALTH_CONSENT: ConsentType = 'health_data_storage';

export type ConsentView = {
  type: ConsentType;
  granted: boolean;
  policy_version: string;
  decided_at: string | null;
};

export type PrivacyRequestView = {
  id: string;
  kind: PrivacyRequestKind;
  status: string;
  requested_at: string;
  execute_after: string;
  completed_at: string | null;
  download_expires_at: string | null;
};

/**
 * docs/13 §9 — the data-subject rights, built as features.
 *
 * Nothing here is a background convenience: an export is evidence that access was given, and an
 * erasure is a promise with a date on it. Both leave a `privacy_request` row precisely so the date
 * can be shown later.
 */
@Injectable()
export class PrivacyService {
  constructor(
    @InjectRepository(PrivacyRequestEntity)
    private readonly requests: Repository<PrivacyRequestEntity>,
    @InjectRepository(ConsentEntity)
    private readonly consentRows: Repository<ConsentEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly notifications: NotificationsService,
    private readonly dataSource: DataSource,
  ) {}

  /// What this person has agreed to, as it stands. `consent` is append-only, so the current answer
  /// is the newest row per type — never an UPDATE (docs/13 §3).
  async consents(userId: number): Promise<ConsentView[]> {
    const rows = await this.consentRows.find({
      where: { userId },
      order: { grantedAt: 'ASC' },
    });

    return CONSENT_TYPES.map((type) => {
      const latest = [...rows].reverse().find((row) => row.type === type);
      return {
        type,
        // Marketing defaults OFF (docs/13 §3: "no pre-ticked optional boxes").
        granted: latest?.granted ?? false,
        policy_version: latest?.policyVersion ?? '1.0.0',
        decided_at: latest?.grantedAt?.toISOString() ?? null,
      };
    });
  }

  /// A withdrawal is a new row, never an update — that is what keeps "what were they consenting to
  /// when we stored that field?" answerable.
  async setConsent(
    userId: number,
    type: ConsentType,
    granted: boolean,
    policyVersion = '1.0.0',
  ): Promise<ConsentView[]> {
    await this.consentRows.save(
      this.consentRows.create({ userId, type, granted, policyVersion }),
    );

    return this.consents(userId);
  }

  /// Whether plan generation is allowed to run at all (docs/13 §3).
  async mayProcessHealth(userId: number): Promise<boolean> {
    const current = await this.consents(userId);
    return current.find((c) => c.type === HEALTH_CONSENT)?.granted ?? false;
  }

  async open(userId: number): Promise<PrivacyRequestView[]> {
    const rows = await this.requests.find({
      where: { userId },
      order: { createdAt: 'DESC' },
      take: 20,
    });

    return rows.map((row) => this.toView(row));
  }

  /**
   * docs/13 §9: an export bundle, built now.
   *
   * Synchronous rather than queued: one person's diary is a few thousand rows, BullMQ is not wired
   * for this, and a job that needs a worker running is a right that silently stops being honoured
   * the day the worker dies. If the bundles ever grow, this is the thing to move.
   */
  async requestExport(
    userId: number,
    now = new Date(),
  ): Promise<PrivacyRequestView> {
    const bundle = await this.buildBundle(userId);

    const row = await this.requests.save(
      this.requests.create({
        userId,
        kind: 'export',
        status: 'done',
        executeAfter: now,
        completedAt: now,
        downloadExpiresAt: exportExpiresAt(now),
        summary: bundle.counts,
      }),
    );

    return this.toView(row);
  }

  /// The bundle itself, read back for download while the link is alive.
  async bundleFor(
    userId: number,
    requestId: string,
    now = new Date(),
  ): Promise<Record<string, unknown>> {
    const row = await this.requests.findOne({
      where: { id: requestId, userId, kind: 'export' },
    });

    if (!row || row.status !== 'done') {
      throw new NotFoundException({
        error: {
          code: 'EXPORT_NOT_FOUND',
          user_message: 'We could not find that export.',
        },
      });
    }

    if (row.downloadExpiresAt && now > row.downloadExpiresAt) {
      throw new NotFoundException({
        error: {
          code: 'EXPORT_EXPIRED',
          user_message:
            'That download link has expired. Ask for a new copy and we will build it again.',
        },
      });
    }

    return (await this.buildBundle(userId)).data;
  }

  /**
   * docs/13 §9: erasure, after a seven-day cooling-off.
   *
   * One open request at a time. Asking twice is one intention, not two — and two rows would each
   * carry their own dates, which is how an account gets erased earlier than it was promised.
   */
  async requestDelete(
    userId: number,
    now = new Date(),
  ): Promise<PrivacyRequestView> {
    const existing = await this.pendingDelete(userId);
    if (existing) {
      throw new ConflictException({
        error: {
          code: 'DELETE_ALREADY_REQUESTED',
          user_message: 'Your account is already scheduled for deletion.',
        },
      });
    }

    const row = await this.requests.save(
      this.requests.create({
        userId,
        kind: 'delete',
        status: 'pending',
        executeAfter: erasureDueAt(now),
      }),
    );

    await this.notifications.notify({
      userId,
      kind: 'account_deletion_requested',
      contentClass: 'service',
      title: 'Your account is scheduled for deletion',
      body: `Nothing is deleted before ${erasureDueAt(now).toDateString()}. You can stop this at any time until then.`,
      data: { request_id: row.id },
      alsoEmail: true,
    });

    return this.toView(row);
  }

  /**
   * Stop it. docs/13 §6 offers "a chance to retain by logging in"; this is that chance as an
   * explicit act rather than a side effect of signing in — somebody who logs in to download their
   * export has not changed their mind about leaving, and guessing that they have is worse than
   * asking.
   */
  async cancelDelete(userId: number, now = new Date()): Promise<void> {
    const pending = await this.pendingDelete(userId);
    if (!pending) {
      throw new NotFoundException({
        error: {
          code: 'NO_DELETE_PENDING',
          user_message: 'There is no deletion to stop.',
        },
      });
    }

    pending.status = 'cancelled';
    pending.completedAt = now;
    await this.requests.save(pending);

    await this.notifications.notify({
      userId,
      kind: 'account_deletion_cancelled',
      contentClass: 'service',
      title: 'Your account is staying',
      body: 'The deletion has been stopped. Nothing was removed.',
      alsoEmail: true,
    });
  }

  /**
   * The erasure itself: a real delete of the health rows, and a tombstone where the person was.
   *
   * docs/13 §6 is explicit that this is not a `deleted_at` flag on everything — the health data
   * goes. What stays is the shape the law requires to stay: payments and invoices for eight years
   * (Companies Act / GST), consent records for seven as evidence of lawful basis, and the audit log
   * for three, immutable. A user row with no name, no number and no address is what lets an invoice
   * from 2024 still be a valid record without being about an identifiable person.
   */
  async erase(
    userId: number,
    now = new Date(),
  ): Promise<Record<string, number>> {
    const counts: Record<string, number> = {};

    await this.dataSource.transaction(async (tx) => {
      const wipe = async (
        entity: Parameters<typeof tx.getRepository>[0],
        key: string,
        where: Record<string, unknown>,
      ) => {
        const result = await tx.getRepository(entity).delete(where);
        counts[key] = result.affected ?? 0;
      };

      await wipe(FoodLogEntity, 'food_logs', { userId });
      await wipe(MeasurementEntity, 'measurements', { userId });
      await wipe(PlanEntity, 'plans', { userId });
      // ADR-013: the training log and plan. The account row stays as a tombstone, so nothing
      // cascades — each table is named here.
      await wipe(GymWorkoutEntity, 'gym_workouts', { userId });
      await wipe(GymRoutineEntity, 'gym_routines', { userId });
      await wipe(GymProfileEntity, 'gym_profile', { userId });
      await wipe(ExerciseEntity, 'gym_custom_exercises', {
        ownerUserId: userId,
      });
      await wipe(HealthProfileEntity, 'health_profiles', { userId });
      await wipe(ProfileEntity, 'profiles', { userId });

      // The tombstone. Not a delete: an invoice has to keep pointing at a row.
      await tx.getRepository(UserEntity).update(
        { id: userId },
        {
          email: null,
          phone: null,
          firstName: null,
          lastName: null,
          socialId: null,
          password: undefined,
          isDemo: false,
        },
      );
      await tx.getRepository(UserEntity).softDelete({ id: userId });
      counts.user_tombstoned = 1;
    });

    const request = await this.pendingDelete(userId);
    if (request) {
      request.status = 'done';
      request.completedAt = now;
      request.summary = counts;
      await this.requests.save(request);
    }

    return counts;
  }

  /// docs/13 §6's retention table, for the rows whose clock is "last activity". Counts only.
  async retentionCutoffs(now = new Date()): Promise<Record<string, string>> {
    return Promise.resolve({
      health: retentionCutoff(
        now,
        RETENTION_DAYS.healthAfterInactivity,
      ).toISOString(),
      meal_photos: retentionCutoff(
        now,
        RETENTION_DAYS.mealPhotos,
      ).toISOString(),
      screening: retentionCutoff(now, RETENTION_DAYS.screening).toISOString(),
      tickets: retentionCutoff(
        now,
        RETENTION_DAYS.ticketsAfterClosure,
      ).toISOString(),
    });
  }

  private async pendingDelete(
    userId: number,
  ): Promise<PrivacyRequestEntity | null> {
    const rows = await this.requests.find({
      where: { userId, kind: 'delete' },
      order: { createdAt: 'DESC' },
      take: 5,
    });

    return (
      rows.find((r) => r.status === 'pending' || r.status === 'notified') ??
      null
    );
  }

  /**
   * Everything this person's account holds, in one object.
   *
   * Reads through the DataSource rather than injecting nine repositories: the list of tables a
   * person's data lives in grows with the product, and a constructor that has to be edited for
   * every new table is a constructor somebody will forget to edit.
   */
  private async buildBundle(userId: number): Promise<{
    data: Record<string, unknown>;
    counts: Record<string, number>;
  }> {
    const tables: [
      string,
      Parameters<DataSource['getRepository']>[0],
      Record<string, unknown>,
    ][] = [
      ['profile', ProfileEntity, { userId }],
      ['health_profile', HealthProfileEntity, { userId }],
      ['consents', ConsentEntity, { userId }],
      ['measurements', MeasurementEntity, { userId }],
      ['food_logs', FoodLogEntity, { userId }],
      ['plans', PlanEntity, { userId }],
      ['gym_profile', GymProfileEntity, { userId }],
      ['gym_routines', GymRoutineEntity, { userId }],
      ['gym_workouts', GymWorkoutEntity, { userId }],
      ['gym_custom_exercises', ExerciseEntity, { ownerUserId: userId }],
    ];

    const data: Record<string, unknown> = {};
    const counts: Record<string, number> = {};

    const user = await this.users.findOne({ where: { id: userId } });
    data.account = user
      ? {
          user_id: user.id,
          email: user.email,
          phone: user.phone,
          first_name: user.firstName,
          last_name: user.lastName,
          created_at: user.createdAt,
        }
      : null;

    for (const [key, entity, where] of tables) {
      const rows = await this.dataSource.getRepository(entity).find({ where });
      data[key] = rows;
      counts[key] = rows.length;
    }

    data.exported_at = new Date().toISOString();
    return { data, counts };
  }

  private toView(row: PrivacyRequestEntity): PrivacyRequestView {
    return {
      id: row.id,
      kind: row.kind,
      status: row.status,
      requested_at: row.createdAt.toISOString(),
      execute_after: row.executeAfter.toISOString(),
      completed_at: row.completedAt?.toISOString() ?? null,
      download_expires_at: row.downloadExpiresAt?.toISOString() ?? null,
    };
  }
}
