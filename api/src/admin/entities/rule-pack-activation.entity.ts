import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * Which rule pack is live, and who put it there (docs/09 §9: "super_admin only, requires
 * reviewed_by").
 *
 * Append-only, like `audit_log` and for the same reason: the active version is the newest row, so
 * the table is also the history of every change to the numbers that decide what people eat. A
 * rollback is a new row naming the older version, never an edit.
 */
@Entity({ name: 'rule_pack_activation' })
export class RulePackActivationEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /// A pack version on disk, e.g. `1.0.0`.
  @Column({ type: 'varchar' })
  version: string;

  @Column()
  activatedByUserId: number;

  /// docs/09 §9's `reviewed_by`. Somebody other than the person activating it: two people, because
  /// the numbers in a pack are the ones docs/05 §2's safety floors are made of.
  @Column()
  reviewedByUserId: number;

  /// What was checked. Free text, written for whoever reads this table in a year.
  @Column({ type: 'varchar', nullable: true })
  note: string | null;

  @Index()
  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
