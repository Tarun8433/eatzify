import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';
import type { PlateEstimate } from './plate-estimate';

/// One scan made: the daily count, and between "scan" and "yes" the estimate and the photo it was
/// made from (D-240). An unconfirmed scan's photo is deleted within a day.
@Entity({ name: 'food_scan' })
@Index('IDX_food_scan_user_day', ['userId', 'diaryDate'])
export class FoodScanEntity extends BaseEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'integer' })
  userId: number;

  @Column({ type: 'date' })
  diaryDate: string;

  /// Whether the model found food it could estimate — how often scanning helps is the number that
  /// decides whether it stays.
  @Column({ type: 'boolean' })
  matched: boolean;

  /// The pending photo, relative to the private photo store; null once deleted or handed to an entry.
  @Column({ type: 'varchar', nullable: true })
  photoPath: string | null;

  /// The model's per-item estimate, kept so "yes" logs exactly what the user was shown.
  @Column({ type: 'jsonb', nullable: true })
  estimate: PlateEstimate | null;

  /// The diary entry this scan became, once confirmed.
  @Column({ type: 'uuid', nullable: true })
  foodLogId: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
