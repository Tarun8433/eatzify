import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  PrimaryColumn,
} from 'typeorm';

/// D-236. An offer the admin hands out: a code, a percentage off, a budget of uses, an expiry.
///
/// Deliberately ONE kind of discount (a percentage, capped at 90) — a flat-amount coupon can go
/// below zero when prices change, and a 100 % coupon creates a zero-amount gateway order. The
/// count of uses is a budget the admin sets, not a suggestion; redemption increments it only on
/// the webhook that confirms payment, so an abandoned checkout never burns a use.
@Entity({ name: 'coupon' })
export class CouponEntity extends BaseEntity {
  /// Stored UPPERCASE; matched case-insensitively at checkout.
  @PrimaryColumn({ type: 'varchar' })
  code: string;

  @Column({ type: 'integer' })
  percentOff: number;

  @Column({ type: 'integer' })
  maxUses: number;

  @Column({ type: 'integer', default: 0 })
  usedCount: number;

  @Column({ type: 'timestamptz', nullable: true })
  expiresAt: Date | null;

  @Column({ type: 'boolean', default: true })
  active: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
