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

  /// Admin panel plan, Phase C: what the offer card says.
  @Column({ type: 'varchar', length: 80, nullable: true })
  title: string | null;

  @Column({ type: 'varchar', length: 300, nullable: true })
  description: string | null;

  @Column({ type: 'varchar', length: 500, nullable: true })
  bannerUrl: string | null;

  /// Not usable before this. Null: from creation.
  @Column({ type: 'timestamptz', nullable: true })
  startsAt: Date | null;

  /// `new_users`: only someone who has never paid before.
  @Column({ type: 'varchar', default: 'all' })
  eligibility: 'all' | 'new_users';

  /// Only for this tier's plans. Null: any.
  @Column({ type: 'varchar', nullable: true })
  tier: 'BASIC' | 'PRO' | null;

  @CreateDateColumn()
  createdAt: Date;
}
