import {
  BaseEntity,
  Column,
  Entity,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/// What Cashfree charges for one tier and length, set in the admin panel (payments plan, Phase 3).
/// Paise, GST-inclusive: ₹249 is 24900. Play and App Store prices are set in their own consoles.
/// Extends BaseEntity for AdminJS, like FoodEntity.
@Entity({ name: 'tier_price' })
export class TierPriceEntity extends BaseEntity {
  @PrimaryColumn({ type: 'varchar' })
  tier: string;

  @PrimaryColumn({ type: 'varchar' })
  duration: string;

  /// BIGINT paise (api rule 3). TypeORM hands a bigint back as a string.
  @Column({ type: 'bigint' })
  pricePaise: string;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
