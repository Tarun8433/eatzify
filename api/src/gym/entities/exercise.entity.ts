import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/// The exercise library (D-244) and each user's own exercises. `ownerUserId` NULL is the shared
/// library; a custom exercise belongs to exactly one person and is never shown to anyone else.
@Entity({ name: 'exercise' })
export class ExerciseEntity extends BaseEntity {
  /// Dataset ids are the upstream 4-digit ids ('0001'); custom ones start with 'c'.
  @PrimaryColumn({ type: 'varchar', length: 40 })
  id: string;

  @Column({ type: 'varchar' })
  name: string;

  @Column({ type: 'varchar' })
  bodyPart: string;

  @Column({ type: 'varchar' })
  equipment: string;

  /// The primary muscle, in the dataset's vocabulary ('pectorals', 'lats', …).
  @Column({ type: 'varchar' })
  target: string;

  @Column({ type: 'jsonb', default: () => "'[]'" })
  secondaryMuscles: string[];

  @Column({ type: 'jsonb', default: () => `'{"en":[],"hi":[]}'` })
  steps: { en: string[]; hi: string[] };

  /// A custom exercise's own words, in place of steps.
  @Column({ type: 'text', nullable: true })
  description: string | null;

  /// The upstream media id. Unused until media is licensed (D-243).
  @Column({ type: 'varchar', nullable: true })
  mediaKey: string | null;

  /// Which `energy_reference.activity` prices a set of it (D-242).
  @Column({ type: 'varchar' })
  energyActivity: string;

  @Column({ type: 'boolean', default: false })
  isBodyweight: boolean;

  @Index()
  @Column({ type: 'integer', nullable: true })
  ownerUserId: number | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
