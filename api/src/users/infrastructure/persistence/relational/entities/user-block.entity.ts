import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

export const BLOCK_REASONS = [
  'spam',
  'fraud',
  'abuse',
  'suspicious',
  'policy',
  'other',
] as const;
export type BlockReason = (typeof BLOCK_REASONS)[number];

/// Admin panel plan, Phase A: one row per block. Lifting a block stamps `liftedAt` rather than
/// deleting the row, so a person's moderation history survives an unblock.
@Entity({ name: 'user_block' })
export class UserBlockEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  reason: BlockReason;

  @Column({ type: 'varchar', length: 500, nullable: true })
  note: string | null;

  @Column()
  blockedBy: number;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  blockedAt: Date;

  /// Null is permanent.
  @Column({ type: 'timestamptz', nullable: true })
  until: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  liftedAt: Date | null;

  /// Null when it lifted itself on expiry.
  @Column({ type: 'int', nullable: true })
  liftedBy: number | null;
}
