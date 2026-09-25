import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// docs/11 §5 and §9. `failed` is terminal; `paid` moves only to `refunded`, and only within the
/// window docs/11 §9 allows.
export const ORDER_STATUS = ['created', 'paid', 'failed', 'refunded'] as const;
export type OrderStatus = (typeof ORDER_STATUS)[number];

/// What the order buys. An upgrade is charged the prorated difference (docs/11 §7), so it has to
/// be told apart from a plain purchase when the payment lands.
export const ORDER_KINDS = ['purchase', 'upgrade'] as const;
export type OrderKind = (typeof ORDER_KINDS)[number];

/**
 * One attempt to buy a subscription.
 *
 * Separate from `subscription` on purpose. A subscription is what someone HAS; an order is what
 * they tried to pay, including the tries that failed — and a failed payment is the row support
 * needs most. Nothing here is ever mutated into a different purchase: a second attempt is a second
 * row.
 */
@Entity({ name: 'payment_order' })
export class PaymentOrderEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Index()
  @Column()
  userId: number;

  /// The id Cashfree knows this order by, and the one a webhook arrives carrying. Ours, not
  /// theirs: we generate it so a webhook can be matched without a second API call.
  @Index({ unique: true })
  @Column({ type: 'varchar' })
  cashfreeOrderId: string;

  @Column({ type: 'varchar' })
  tier: string;

  @Column({ type: 'varchar' })
  duration: string;

  /**
   * Integer paise. `api/CLAUDE.md` rule 3 — never a float, never rupees-as-decimal.
   *
   * Taken from the price matrix at checkout, never from the request body: a client that could name
   * its own price would name ₹1. Stored so a later price change cannot rewrite what someone paid.
   */
  @Column({ type: 'bigint' })
  amountPaise: string;

  @Column({ type: 'varchar', default: 'created' })
  status: OrderStatus;

  @Column({ type: 'varchar', default: 'purchase' })
  kind: OrderKind;

  /// What docs/11 §7's proration knocked off this order. Zero on a plain purchase; kept so a
  /// receipt can show the arithmetic the person was quoted.
  @Column({ type: 'bigint', default: 0 })
  creditPaise: string;

  @Column({ type: 'timestamptz', nullable: true })
  refundedAt: Date | null;

  /// Cashfree's handle for the checkout session, which the app hands to their SDK. Null in stub
  /// mode and until the gateway answers.
  @Column({ type: 'varchar', nullable: true })
  paymentSessionId: string | null;

  /// docs/09: a retried POST must not create a second order. Unique where present, the same shape
  /// `plan` uses.
  @Index({ unique: true, where: '"idempotencyKey" IS NOT NULL' })
  @Column({ type: 'varchar', nullable: true })
  idempotencyKey: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  paidAt: Date | null;

  /// D-236: the offer applied at checkout, and what it took off. Stored on the order so a later
  /// coupon change cannot rewrite what someone actually paid.
  @Column({ type: 'varchar', nullable: true })
  couponCode: string | null;

  @Column({ type: 'bigint', default: 0 })
  discountPaise: string;

  /// Why a payment failed, as the gateway described it. For support, never for the user (rule 7).
  @Column({ type: 'varchar', nullable: true })
  failureReason: string | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
