import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';
import type { GrantScope } from './coach-grant.entity';

export const INVITE_STATUS = [
  'pending',
  'accepted',
  'declined',
  'expired',
] as const;
export type InviteStatus = (typeof INVITE_STATUS)[number];

/**
 * A coach asking one person to work with them (docs/09 §6).
 *
 * **An invite is a REQUEST, never an assignment.** docs/10 §3: "a coach may request a scope; only
 * the client can grant it." Accepting is what creates the grant; this row only carries the ask.
 *
 * Addressed by phone because the person may not have an account yet — which is also why the
 * response to creating one must never reveal whether they do (docs/09 §3: "never return whether a
 * number exists").
 */
@Entity({ name: 'coach_invite' })
@Index(['phoneE164', 'status'])
export class CoachInviteEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'int' })
  coachUserId: number;

  /// The number the coach typed. Stored rather than hashed because the coach has to be able to see
  /// which of their own invites is still outstanding, and they supplied it in the first place —
  /// a hash would hide it from the only person who already knows it.
  @Column({ type: 'varchar' })
  phoneE164: string;

  /// What the coach is ASKING for. Capped by their level at creation, and capped again when the
  /// grant is actually made — a coach who is demoted between the two must not keep the wider ask.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  scopes: GrantScope[];

  @Column({ type: 'varchar', default: 'pending' })
  status: InviteStatus;

  /// An unanswered invite is not a standing offer. Without an expiry, a number typed once would
  /// carry a pending request for as long as the table exists.
  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  @Column({ type: 'timestamptz', nullable: true })
  respondedAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
