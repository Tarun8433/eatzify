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
import { FoodEntity } from '../../foods/entities/food.entity';

/// docs/08 §food_logs.
///
/// Nutrition is COPIED onto the row rather than joined from `food` at read time. That is the whole
/// point: correcting a food's sodium next month must not silently rewrite what somebody ate last
/// week. The `foodId` link is kept for provenance, not for arithmetic.
@Entity({ name: 'food_log' })
@Index(['userId', 'diaryDate'])
export class FoodLogEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  /// Server-resolved 04:00 IST diary day (CLAUDE.md rule 8).
  @Column({ type: 'date' })
  diaryDate: string;

  @Column({ type: 'varchar' })
  slot: string;

  @ManyToOne(() => FoodEntity, { onDelete: 'SET NULL', nullable: true })
  @JoinColumn({ name: 'foodId' })
  food: FoodEntity | null;

  @Column({ type: 'uuid', nullable: true })
  foodId: string | null;

  /// Set when the user logged something not in the database.
  @Column({ type: 'varchar', nullable: true })
  customName: string | null;

  @Column({ type: 'numeric', precision: 7, scale: 1 })
  quantityG: string;

  /// What the user chose, e.g. "2 katori". Kept so the diary can show it back in their words rather
  /// than in grams — docs/03 §units makes the household measure primary.
  @Column({ type: 'varchar', nullable: true })
  measureLabel: string | null;

  @Column({ type: 'numeric', precision: 7, scale: 1 })
  kcal: string;

  @Column({ type: 'numeric', precision: 6, scale: 1 })
  proteinG: string;

  @Column({ type: 'numeric', precision: 6, scale: 1 })
  carbG: string;

  @Column({ type: 'numeric', precision: 6, scale: 1 })
  fatG: string;

  /// Null on rows from before D-136 and on custom entries (nobody types their fibre): "not
  /// recorded", which is not the same claim as zero.
  @Column({ type: 'numeric', precision: 6, scale: 1, nullable: true })
  fibreG: string | null;

  @Column({ type: 'varchar', default: 'manual' })
  source: string;

  /// docs/08: editable for 48 h, then locked. A diary that can be rewritten indefinitely is not a
  /// record of what happened.
  @Column({ type: 'timestamptz', nullable: true })
  lockedAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  loggedAt: Date;
}
