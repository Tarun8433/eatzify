import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// docs/08 §1. One row per user per kind per **diary day** — the unique constraint is load-bearing,
/// not hygiene: docs/08 says it plus `isSuspect` are what prevent the old build's "−30.0 kg change"
/// readout. Two weigh-ins on one day overwrite; they do not both count.
@Entity({ name: 'measurement' })
@Index(['userId', 'kind', 'diaryDate'], { unique: true })
export class MeasurementEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  kind: string;

  /// 10,2 not 7,2: `BOUNDS.steps` allows 100000, which needs six digits before the point (D-96).
  @Column({ type: 'numeric', precision: 10, scale: 2 })
  value: string;

  @Column({ type: 'varchar' })
  unit: string;

  /// The diary day (04:00 IST boundary), never the calendar day. CLAUDE.md rule 8.
  @Column({ type: 'date' })
  diaryDate: string;

  @Column({ type: 'varchar', default: 'manual' })
  source: string;

  /// Set when the delta rule trips. Suspect rows are stored but excluded from the moving average
  /// and from the adjuster (docs/16) — a typo must not silently reshape someone's trend.
  @Column({ type: 'boolean', default: false })
  isSuspect: boolean;

  @CreateDateColumn({ type: 'timestamptz' })
  recordedAt: Date;
}
