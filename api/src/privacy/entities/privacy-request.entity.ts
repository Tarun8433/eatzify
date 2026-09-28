import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/// docs/13 §9: access and erasure, "as features, not tickets".
export const PRIVACY_REQUEST_KINDS = ['export', 'delete'] as const;
export type PrivacyRequestKind = (typeof PRIVACY_REQUEST_KINDS)[number];

/**
 * `pending` — asked for, waiting out the cooling-off (deletion) or the build (export).
 * `notified` — docs/13 §6's 48-hour warning has gone out. Deletion only.
 * `done` — the export is downloadable, or the erasure has run.
 * `cancelled` — the person changed their mind, or the download expired.
 */
export const PRIVACY_REQUEST_STATUSES = [
  'pending',
  'notified',
  'done',
  'cancelled',
] as const;
export type PrivacyRequestStatus = (typeof PRIVACY_REQUEST_STATUSES)[number];

/**
 * One exercise of a data-subject right (docs/13 §9).
 *
 * Kept as a row rather than done inline for two reasons the law cares about: an erasure has a
 * seven-day cooling-off and a 48-hour warning before it runs, and both need somewhere to live; and
 * "we did this, on this date, because they asked on that date" is the evidence that the right was
 * honoured. A deletion that leaves no trace of having been requested cannot be shown to have
 * happened on time.
 */
@Entity({ name: 'privacy_request' })
@Index(['status', 'executeAfter'])
export class PrivacyRequestEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  kind: PrivacyRequestKind;

  @Column({ type: 'varchar', default: 'pending' })
  status: PrivacyRequestStatus;

  /// When the sweep may act. Deletion: seven days out (docs/13 §9's cooling-off). Export: now.
  @Column({ type: 'timestamptz' })
  executeAfter: Date;

  /// docs/13 §6: "notify the user 48 hours before erasure … with a chance to retain".
  @Column({ type: 'timestamptz', nullable: true })
  notifiedAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  completedAt: Date | null;

  /// Where the export bundle landed, and when the link stops working (docs/13 §9: 24 hours).
  @Column({ type: 'varchar', nullable: true })
  filePath: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  downloadExpiresAt: Date | null;

  /// Counts only — how many rows of what were erased. Never what they said (api rule 5).
  @Column({ type: 'jsonb', default: () => "'{}'" })
  summary: Record<string, unknown>;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
