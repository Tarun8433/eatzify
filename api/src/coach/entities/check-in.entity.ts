import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';
import type { CheckInStatus } from '../check-in-rules';

/// docs/02 FR-5.2's queue, one row per coach per client per week.
///
/// A row exists so the review can be RECORDED: docs/09 §6's `POST /coach/checkins/{id}/complete`
/// takes notes and actions, and notes with nowhere to live are notes nobody writes.
@Entity({ name: 'check_in' })
@Index(['coachUserId', 'status'])
export class CheckInEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  coachUserId: number;

  @Column()
  clientUserId: number;

  /// The Monday of the week it belongs to — a diary date, never an instant (rule 4).
  @Column({ type: 'date' })
  dueOn: string;

  @Column({ type: 'varchar', default: 'due' })
  status: CheckInStatus;

  @Column({ type: 'timestamptz', nullable: true })
  completedAt: Date | null;

  /// What the coach wrote. Health data by any reading — it is about one person's eating — so it
  /// lives under the same grant rules as everything else the coach sees.
  @Column({ type: 'text', nullable: true })
  notes: string | null;

  /// What they agreed to do next: short lines, not free text with a different name.
  @Column({ type: 'jsonb', nullable: true })
  actions: string[] | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
