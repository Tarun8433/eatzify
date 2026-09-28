import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/// docs/10 §3. What a client has allowed one coach to see. A coach may REQUEST a scope; only the
/// client may grant it.
export const GRANT_SCOPES = [
  /// Display name, age band, goal, plan tier.
  'basic',
  /// Weight series, adherence %, steps, streaks.
  'progress',
  'plan_view',
  'plan_edit',
  'chat',
  /// Declared conditions and allergies. Never the eating-disorder screening answer — docs/10 §5.5
  /// puts that beyond every role, grant or no grant.
  'health_conditions',
] as const;

export type GrantScope = (typeof GRANT_SCOPES)[number];

/// `paused` rather than deleted on revoke or expiry (docs/10 §3): the assignment survives so the
/// coach's UI can say "access ended" instead of showing the last thing it cached.
export const GRANT_STATUS = ['active', 'paused'] as const;
export type GrantStatus = (typeof GRANT_STATUS)[number];

/// One client's permission to one coach.
///
/// **The row IS the access.** docs/10 §1: "the level does not grant access. The consent grant
/// does." A coach_l3 without a row here sees nothing at all; the role only caps which scopes this
/// row is allowed to contain.
@Entity({ name: 'coach_grant' })
@Index(['coachUserId', 'status'])
export class CoachGrantEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'int' })
  clientUserId: number;

  @Column({ type: 'int' })
  coachUserId: number;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  scopes: GrantScope[];

  @Column({ type: 'varchar', default: 'active' })
  status: GrantStatus;

  /// docs/10 §3: subscription end, or 180 days, whichever is SOONER. Stored rather than derived so
  /// a lapsed grant stays lapsed even if the subscription is later extended — re-granting is the
  /// client's decision to make again, not something a renewal does on their behalf.
  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  /// Why it ended, for the audit trail. Null while active.
  @Column({ type: 'varchar', nullable: true })
  endedReason: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  endedAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
