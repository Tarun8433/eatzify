import {
  Column,
  Entity,
  JoinColumn,
  OneToOne,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';
import type { DayOverride, WorkingWeight } from '../gym-types';

/// One per user, created on first use. The weekly schedule, one-off day changes, the confirmed
/// working weight per exercise, and the in-workout preferences.
@Entity({ name: 'gym_profile' })
export class GymProfileEntity {
  @PrimaryColumn({ type: 'integer' })
  userId: number;

  @OneToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  /// ISO weekday ('1' Monday … '7' Sunday) → routine id. A missing day is a rest day.
  @Column({ type: 'jsonb', default: () => "'{}'" })
  week: Record<string, number>;

  /// Diary date → a routine id or 'rest' for that one day.
  @Column({ type: 'jsonb', default: () => "'{}'" })
  dayOverrides: Record<string, DayOverride>;

  /// Exercise id → the confirmed working weight. Only ever raised.
  @Column({ type: 'jsonb', default: () => "'{}'" })
  workingWeights: Record<string, WorkingWeight>;

  @Column({ type: 'integer', default: 90 })
  restSec: number;

  @Column({ type: 'varchar', default: 'off' })
  effortScale: string;

  @Column({ type: 'boolean', default: true })
  keepAwake: boolean;

  @Column({ type: 'boolean', default: true })
  sound: boolean;

  @Column({ type: 'varchar', default: 'male' })
  bodyFigure: string;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
