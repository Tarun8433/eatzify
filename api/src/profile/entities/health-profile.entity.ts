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

/// docs/09 §4: versioned, never updated in place — `PATCH /profile/health` writes a new row.
/// A plan must be traceable to the exact health profile it was generated from, so history is the
/// point of this table, not a nicety.
@Entity({ name: 'health_profile' })
@Index(['userId', 'version'], { unique: true })
export class HealthProfileEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  @Column({ type: 'int' })
  version: number;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  conditions: string[];

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  allergies: string[];

  /// docs/05 §4 screening answers. Stored because a gate decision must be auditable after the fact.
  @Column({ type: 'boolean', nullable: true })
  screenedSpecialDiet: boolean | null;

  @Column({ type: 'boolean', nullable: true })
  screenedInsulinOrKidney: boolean | null;

  @Column({ type: 'boolean', nullable: true })
  screenedEatingDisorder: boolean | null;

  /// Free text. See the DTO for why this is not a structured drug list.
  @Column({ type: 'text', nullable: true })
  medications: string | null;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  digestiveSymptoms: string[];

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  injuries: string[];

  /// FR-1.3 — female users only. Null for everyone else, and the service enforces that rather than
  /// trusting the client to omit them.
  @Column({ type: 'varchar', nullable: true })
  menstrualRegularity: string | null;

  @Column({ type: 'boolean', nullable: true })
  pregnantOrBreastfeeding: boolean | null;

  @Column({ type: 'boolean', nullable: true })
  heavyBleedingOrPain: boolean | null;

  @Column({ type: 'boolean', nullable: true })
  hormonalMedication: boolean | null;

  /// The gates that fired when this version was written.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  gates: string[];

  @CreateDateColumn()
  createdAt: Date;
}
