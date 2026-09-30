import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  PrimaryColumn,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/// docs/12 §5. The section 194H rate, dated so an old payout can be recomputed. Rows come from the
/// CA; none are seeded.
@Entity({ name: 'tds_rate' })
export class TdsRateEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'integer' })
  rateBps: number;

  @Column({ type: 'timestamptz' })
  effectiveFrom: Date;

  @Column({ type: 'text', nullable: true })
  note: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}

export const KYC_STATUS = ['pending', 'verified', 'rejected'] as const;
export type KycStatus = (typeof KYC_STATUS)[number];

/// docs/12 §5: what must be true before a first payout. Last four digits only — the full PAN and
/// bank account belong to the accounting system the money is sent from.
@Entity({ name: 'partner_kyc' })
export class PartnerKycEntity extends BaseEntity {
  @PrimaryColumn()
  partnerUserId: number;

  @Column({ type: 'text' })
  panLast4: string;

  @Column({ type: 'text' })
  bankLast4: string;

  @Column({ type: 'text', nullable: true })
  gstin: string | null;

  /// D-255: what an admin needs to send the money. The full PAN and account number are sealed
  /// (`utils/field-crypto.ts`) and only opened on the admin desk behind a second factor.
  @Column({ type: 'text', nullable: true })
  holderName: string | null;

  @Column({ type: 'text', nullable: true })
  ifsc: string | null;

  @Column({ type: 'text', nullable: true })
  panSealed: string | null;

  @Column({ type: 'text', nullable: true })
  accountSealed: string | null;

  @Column({ type: 'text', default: 'pending' })
  status: KycStatus;

  /// docs/12 §7: a changed bank account freezes payouts for 7 days.
  @Column({ type: 'timestamptz' })
  bankChangedAt: Date;

  @Column({ type: 'timestamptz', nullable: true })
  verifiedAt: Date | null;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}

export const PAYOUT_STATUS = ['pending_approval', 'paid', 'cancelled'] as const;
export type PayoutStatus = (typeof PAYOUT_STATUS)[number];

/// One partner's payable balance for one monthly run (docs/12 §5). Paid by a human, outside this
/// server, and marked paid here with the bank's UTR.
@Entity({ name: 'payout' })
export class PayoutEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  partnerUserId: number;

  /// The month the run was for (`YYYY-MM`). Earlier months' balances that were under the minimum
  /// roll into it.
  @Column({ type: 'text' })
  periodMonth: string;

  /// BIGINT paise, as strings — a JS number cannot hold every BIGINT (api rule 3).
  @Column({ type: 'bigint' })
  grossPaise: string;

  @Column({ type: 'integer' })
  tdsRateBps: number;

  @Column({ type: 'bigint' })
  tdsPaise: string;

  @Column({ type: 'bigint' })
  netPaise: string;

  @Column({ type: 'text', default: 'pending_approval' })
  status: PayoutStatus;

  /// The bank's reference for the transfer. Required once paid (a DB check says so).
  @Column({ type: 'text', nullable: true })
  utr: string | null;

  @Column({ type: 'integer', nullable: true })
  approvedBy: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  paidAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
