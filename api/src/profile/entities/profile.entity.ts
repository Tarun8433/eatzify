import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  OneToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// docs/03 §2. One per user, overwritten in place — the *health* profile is the versioned one.
@Entity({ name: 'profile' })
export class ProfileEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @OneToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column({ unique: true })
  userId: number;

  @Column({ type: 'int' })
  ageYears: number;

  @Column({ type: 'int' })
  heightCm: number;

  @Column({ type: 'numeric', precision: 5, scale: 2 })
  weightKg: string;

  @Column({ type: 'numeric', precision: 5, scale: 2, nullable: true })
  goalWeightKg: string | null;

  @Column({ type: 'varchar' })
  sexAtBirth: string;

  @Column({ type: 'varchar' })
  goal: string;

  @Column({ type: 'varchar' })
  activity: string;

  @Column({ type: 'varchar' })
  foodPreference: string;

  @Column({ type: 'varchar' })
  mealCount: string;

  @Column({ type: 'varchar' })
  lifestyle: string;

  @Column({ type: 'varchar' })
  budgetTier: string;

  @Column({ type: 'varchar', nullable: true })
  name: string | null;

  /// The user's literal goal choice. `goal` above is what the engine plans from.
  @Column({ type: 'varchar', nullable: true })
  goalDeclared: string | null;

  /// "HH:MM", 24-hour. A time of day, not an instant — see the DTO.
  @Column({ type: 'varchar', nullable: true })
  wakeTime: string | null;

  @Column({ type: 'varchar', nullable: true })
  sleepTime: string | null;

  @Column({ type: 'numeric', precision: 3, scale: 1, nullable: true })
  sleepHours: string | null;

  @Column({ type: 'varchar', nullable: true })
  breakfastTime: string | null;

  @Column({ type: 'varchar', nullable: true })
  lunchTime: string | null;

  @Column({ type: 'varchar', nullable: true })
  eveningSnackTime: string | null;

  @Column({ type: 'varchar', nullable: true })
  dinnerTime: string | null;

  /// Dislikes. Never treated as an allergy — see the DTO.
  @Column({ type: 'text', nullable: true })
  foodDislikes: string | null;

  /// Rupees a month (D-78). `budgetTier` is derived from it.
  @Column({ type: 'int', nullable: true })
  budgetMonthlyInr: number | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
