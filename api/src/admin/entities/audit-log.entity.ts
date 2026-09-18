import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/// docs/08 §8. What an admin did, to whom, and why.
///
/// The closed list from docs/10 §4: an admin read of a health field is rejected unless it carries
/// one of these. "Because I wanted to look" is not one of them, and that is the point — a reason
/// drawn from a list is auditable in a way free text never is.
export const AUDIT_REASONS = [
  'support_ticket',
  'fraud_review',
  'data_subject_request',
  'safety_review',
] as const;
export type AuditReason = (typeof AUDIT_REASONS)[number];

/// docs/08 §8 names five; partner review adds two, because a verification nobody is accountable for
/// is not a verification (`coach_application.reviewedByUserId` exists for exactly this reason).
export const AUDIT_ACTIONS = [
  'read_health',
  'export',
  'override_plan',
  'change_price',
  'grant_revoke',
  'coach_verify',
  'coach_reject',
  'read_pii',
  'rule_pack_activate',
] as const;
export type AuditAction = (typeof AUDIT_ACTIONS)[number];

/**
 * Append only (docs/08 §8 revokes UPDATE and DELETE). There is deliberately no `@UpdateDateColumn`
 * and no service method that writes twice to a row: a log the application can edit is not evidence.
 *
 * No PII in the row itself — `api/CLAUDE.md` rule 5 bans name, phone, email, weight and condition
 * from logs, and this table is a log. It records that a health field was read and by whom, never
 * what the field said.
 */
@Entity({ name: 'audit_log' })
export class AuditLogEntity extends BaseEntity {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: string;

  /// Null only for a system actor. A human action always has one.
  @Column({ type: 'int', nullable: true })
  @Index()
  actorUserId: number | null;

  /// Stored as text, not a role id: the roles table can be renumbered, and a log that needs a join
  /// to another mutable table to be read is a log that can change meaning after the fact.
  @Column({ type: 'text' })
  actorRole: string;

  @Column({ type: 'text' })
  action: AuditAction;

  /// The person acted upon. Null for actions that are not about one person (a rule-pack activation).
  @Column({ type: 'int', nullable: true })
  @Index()
  subjectUserId: number | null;

  @Column({ type: 'text' })
  resource: string;

  @Column({ type: 'jsonb', default: () => "'{}'" })
  meta: Record<string, unknown>;

  /// docs/10 §4: required for a health read, absent for everything else.
  @Column({ type: 'text', nullable: true })
  reason: AuditReason | null;

  /// Hashed, never raw. An IP is personal data under the DPDP Act and docs/13 §4 says collect less.
  @Column({ type: 'text', nullable: true })
  ipHash: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
