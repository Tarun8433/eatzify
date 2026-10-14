import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';
import type { StoreProvider } from '../store/store-rules';

export const ATTEMPT_PROVIDERS = ['play', 'app_store'] as const;

export const ATTEMPT_OUTCOMES = [
  'cancelled',
  'failed',
  'pending',
  'purchased',
  'refused',
] as const;
export type AttemptOutcome = (typeof ATTEMPT_OUTCOMES)[number];

/// The app's `PaymentFailureReason` names, plus `serverRefused` for a verify the server turned down.
export const ATTEMPT_REASONS = [
  'storeUnavailable',
  'productUnavailable',
  'alreadyOwned',
  'storeBusy',
  'storeFailed',
  'serverRefused',
] as const;
export type AttemptReason = (typeof ATTEMPT_REASONS)[number];

/**
 * D-266: one Google Play / App Store purchase attempt as the app saw it end, for support. A failed
 * Play attempt never reaches the server otherwise, so the Payments page could not show it.
 *
 * No amount, no card or UPI data, no purchase token: what was asked for, how it ended, and Play's
 * own response code.
 */
@Entity({ name: 'store_purchase_attempt' })
@Index('IDX_store_purchase_attempt_created', ['createdAt'])
@Index('IDX_store_purchase_attempt_user', ['userId', 'createdAt'])
export class StorePurchaseAttemptEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  provider: StoreProvider;

  @Column({ type: 'varchar', length: 100 })
  productId: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  basePlanId: string | null;

  @Column({ type: 'varchar', length: 100, nullable: true })
  offerId: string | null;

  @Column({ type: 'varchar' })
  outcome: AttemptOutcome;

  @Column({ type: 'varchar', length: 40, nullable: true })
  reason: AttemptReason | null;

  /// Play's raw response code, e.g. `BillingResponse.developerError`. Null when it was not one.
  @Column({ type: 'varchar', length: 80, nullable: true })
  storeCode: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
