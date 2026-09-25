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

/// A generated plan. docs/04 §1: `rulePackVersion` and `healthProfileVersion` are stored WITH the
/// plan, not looked up later — a plan issued months ago must be reproducible byte-for-byte for a
/// coach or an audit (docs/16 GV-09), and both inputs move underneath it over time.
@Entity({ name: 'plan' })
@Index(['userId', 'planDate'])
export class PlanEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  /// ISO date. The server owns the diary day (CLAUDE.md rule 8) — never computed client-side.
  @Column({ type: 'date' })
  planDate: string;

  @Column({ type: 'varchar' })
  rulePackVersion: string;

  @Column({ type: 'int' })
  healthProfileVersion: number;

  /// Null when a blocking gate fired. docs/04 §2: a partial plan is worse than no plan.
  @Column({ type: 'jsonb', nullable: true })
  targets: Record<string, number> | null;

  @Column({ type: 'jsonb', nullable: true })
  derived: Record<string, unknown> | null;

  @Column({ type: 'jsonb', default: () => "'[]'" })
  mealTargets: unknown[];

  /// The food itself (D-164). Empty for a plan generated before steps 11 and 13 existed, and for
  /// any plan whose candidate pool came back empty — never null, so no reader has to tell "no food
  /// chosen" from "not asked".
  @Column({ type: 'jsonb', default: () => "'[]'" })
  meals: unknown[];

  @Column({ type: 'jsonb', nullable: true })
  constraints: Record<string, unknown> | null;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  warnings: string[];

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  gates: string[];

  /// docs/09 §4.2 returns `trace_available`; the trace itself is a coach/admin surface.
  @Column({ type: 'jsonb', default: () => "'[]'" })
  trace: unknown[];

  @Column({ type: 'varchar', nullable: true })
  regenerateReason: string | null;

  /// docs/09 §4.2 sends an Idempotency-Key. A retried request must not bill a second generation.
  @Index({ unique: true, where: '"idempotencyKey" IS NOT NULL' })
  @Column({ type: 'varchar', nullable: true })
  idempotencyKey: string | null;

  @CreateDateColumn()
  createdAt: Date;
}
