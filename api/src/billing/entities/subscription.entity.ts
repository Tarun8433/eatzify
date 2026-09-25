import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// docs/11 §5. One row per user; the lifecycle moves through it rather than creating a row per
/// state, so "what is this person entitled to right now" is a single lookup.
@Entity({ name: 'subscription' })
export class SubscriptionEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  /// Not unique any more: docs/11 §7 closes a row and opens another on an upgrade, so a user has
  /// a history. The database forbids a second LIVE one instead (docs/08 §6's `one_live_sub`).
  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar', default: 'FREE' })
  tier: string;

  @Column({ type: 'varchar', default: 'active' })
  status: string;

  /// Null for FREE, which never expires. docs/08 §6 calls this `ends_at`.
  @Column({ type: 'timestamptz', nullable: true })
  currentPeriodEnd: Date | null;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  startsAt: Date;

  /// What was actually paid for this period, in paise. docs/11 §7 prorates an upgrade from it, so
  /// a period with no figure cannot be credited — which is why a trial is worth nothing back.
  @Column({ type: 'bigint', nullable: true })
  paidPaise: string | null;

  /// Which cell of the price matrix this period came from — `PRO:3M`.
  @Column({ type: 'varchar', nullable: true })
  priceKey: string | null;

  @Column({ type: 'boolean', default: false })
  autoRenew: boolean;

  /// docs/11 §8: above ₹15,000 the RBI 2026 framework needs AFA on every debit, so this drives a
  /// different renewal path — assisted, never a silent attempt that will fail.
  @Column({ type: 'boolean', default: false })
  requiresAfa: boolean;

  /// When the person turned renewal off. Access continues to [currentPeriodEnd] (docs/09 §7).
  @Column({ type: 'timestamptz', nullable: true })
  cancelledAt: Date | null;

  /// docs/11 §6. Set only while the period is a trial.
  @Column({ type: 'timestamptz', nullable: true })
  trialEndsAt: Date | null;

  /// Provider-side id, so a webhook can find this row. Null until a real purchase happens.
  @Column({ type: 'varchar', nullable: true })
  providerRef: string | null;

  @Column({ type: 'varchar', nullable: true })
  provider: string | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
