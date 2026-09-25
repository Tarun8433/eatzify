import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/// docs/02 §3 (P3's "ticket triage") and docs/09 §9. A support conversation about one thing.
///
/// docs/03 §5: `new → open → waiting_user → resolved → closed`, reopenable within 7 days.
/// `waiting_user` is a real state, not a nicety: a queue that cannot tell "we owe them an answer"
/// from "they owe us one" is a queue where the first kind quietly ages.
export const TICKET_STATUSES = [
  'new',
  'open',
  'waiting_user',
  'resolved',
  'closed',
] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];

/// docs/03 §5's reopen window, measured from the moment support resolved it.
export const REOPEN_DAYS = 7;

/// A queue where one person can bury everybody else is not a queue. Nothing is deleted; the cap
/// only asks them to use a conversation they already have open.
export const MAX_OPEN_PER_USER = 5;

@Entity({ name: 'ticket' })
@Index(['status', 'lastMessageAt'])
export class TicketEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  subject: string;

  @Column({ type: 'varchar', default: 'new' })
  status: TicketStatus;

  /// docs/09 §1: every response carries `X-Request-Id` and "support tickets quote it". Kept on the
  /// ticket so the logs for the moment it went wrong can actually be found.
  @Column({ type: 'varchar', nullable: true })
  requestId: string | null;

  /// What the queue sorts on. Derived, but stored: sorting a list by "the newest message in each
  /// thread" is a join nobody should pay for on every open.
  @Column({ type: 'timestamptz' })
  lastMessageAt: Date;

  /// Set when support resolves it, which is also where docs/13 §6's two-year retention clock and
  /// docs/03 §5's seven-day reopen window both start.
  @Column({ type: 'timestamptz', nullable: true })
  closedAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
