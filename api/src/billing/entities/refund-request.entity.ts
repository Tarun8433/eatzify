import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

export const REFUND_REQUEST_STATUS = [
  'requested',
  'approved',
  'rejected',
] as const;
export type RefundRequestStatus = (typeof REFUND_REQUEST_STATUS)[number];

/// Admin panel plan, Phase B: a refund asked for after the self-serve window, waiting on a human.
@Entity({ name: 'refund_request' })
export class RefundRequestEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  orderId: string;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar', length: 1000 })
  reason: string;

  @Column({ type: 'varchar', default: 'requested' })
  status: RefundRequestStatus;

  @Column({ type: 'int', nullable: true })
  decidedBy: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  decidedAt: Date | null;

  /// Shown to the person when a request is turned down.
  @Column({ type: 'varchar', length: 1000, nullable: true })
  decisionNote: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
