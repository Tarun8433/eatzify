import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/// docs/12 §2 and §3. A reversal is its own kind because it is its own ROW — an edit would make
/// the ledger unreconcilable.
export const COMMISSION_KINDS = [
  'first_purchase',
  'renewal',
  'bonus',
  'reversal',
] as const;
export type CommissionKind = (typeof COMMISSION_KINDS)[number];

/// docs/12 §4's lifecycle. `accrued` holds for the refund window; `payable` is past it.
export const COMMISSION_STATUS = [
  'accrued',
  'payable',
  'paid',
  'reversed',
] as const;
export type CommissionStatus = (typeof COMMISSION_STATUS)[number];

/**
 * One line of what a partner earned.
 *
 * Append only. A refund inserts a negative entry pointing at the one it reverses rather than
 * editing it, so the sum over a period is always the truth and the history of how it got there
 * survives (docs/12 §3: "offsetting entry, never a delete").
 */
@Entity({ name: 'commission_entry' })
@Index(['partnerUserId', 'periodMonth'])
export class CommissionEntryEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  partnerUserId: number;

  /// Who bought. Never exposed on the earnings endpoint — docs/12 §8 makes a partner's view
  /// aggregate only, because a per-client line would tell an affiliate what one person paid.
  @Column()
  clientUserId: number;

  @Column({ type: 'uuid' })
  paymentOrderId: string;

  @Column({ type: 'text' })
  kind: CommissionKind;

  /**
   * Which rate table this was written against, and the basis points taken from it.
   *
   * Both are stored rather than looked up later. docs/12 §2 wants a historical entry recomputable,
   * and a rate change next year must not silently restate what somebody earned last year.
   */
  @Column({ type: 'text' })
  rateVersion: string;

  @Column({ type: 'int' })
  rateBps: number;

  /// Integer paise throughout (`api/CLAUDE.md` rule 3). `netPaise` is gross minus GST minus any
  /// store fee — docs/12 §2: "Commission is on net revenue, never on gross."
  @Column({ type: 'bigint' })
  grossPaise: string;

  @Column({ type: 'bigint' })
  netPaise: string;

  /// Negative on a reversal. The period total is a plain SUM, which is the point.
  @Column({ type: 'bigint' })
  amountPaise: string;

  @Column({ type: 'text', default: 'accrued' })
  status: CommissionStatus;

  /// `YYYY-MM`. The month the earning belongs to, decided once at write time so a report cannot
  /// drift when it is re-run in a different timezone.
  @Column({ type: 'text' })
  periodMonth: string;

  /// docs/12 §4's refund window. Until this passes the entry is accrued, not payable.
  @Column({ type: 'timestamptz', nullable: true })
  holdUntil: Date | null;

  /// Set on a reversal, pointing at the entry it cancels.
  @Column({ type: 'uuid', nullable: true })
  reversesId: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}

/// docs/12 §2, as a row per cell. Versioned so a historical entry stays recomputable.
@Entity({ name: 'commission_rate' })
export class CommissionRateEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'text' })
  version: string;

  @Column({ type: 'text' })
  tier: string;

  @Column({ type: 'text' })
  kind: 'first_purchase' | 'renewal';

  @Column({ type: 'int' })
  rateBps: number;

  /// docs/12 §2: "Renewal commission is capped at 12 months. Perpetual recurring commission on a
  /// low-ARPU subscription makes your unit economics permanently negative on the best cohorts."
  @Column({ type: 'int', nullable: true })
  renewalMonthsCap: number | null;

  @Column({ type: 'timestamptz' })
  effectiveFrom: Date;
}

/// docs/12 §3. First-touch, locked at signup, never rewritten — the primary key on `userId` is what
/// enforces "no re-attribution ever, including on re-install".
@Entity({ name: 'attribution' })
export class AttributionEntity extends BaseEntity {
  @PrimaryGeneratedColumn('increment')
  userId: number;

  @Index()
  @Column()
  partnerUserId: number;

  @Column({ type: 'text' })
  codeUsed: string;

  @Column({ type: 'text' })
  channel: 'code' | 'link' | 'qr';

  @CreateDateColumn({ type: 'timestamptz' })
  lockedAt: Date;
}

/// The code a partner shares. One per partner, unique across everyone.
@Entity({ name: 'partner_referral' })
export class PartnerReferralEntity extends BaseEntity {
  @PrimaryGeneratedColumn('increment')
  userId: number;

  @Index({ unique: true })
  @Column({ type: 'text' })
  code: string;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
