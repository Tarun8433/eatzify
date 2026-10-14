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

export const OFFER_CHANNELS = ['play', 'cashfree'] as const;
export type OfferChannel = (typeof OFFER_CHANNELS)[number];

/**
 * D-265: one special price for ONE person, made by an admin and sent to them as a link.
 *
 * The link carries only `code`; everything else is here, and the app is answered from this row
 * alone — so editing the link can only ever produce "not found". A Play offer stores Play's ids and
 * no price (Play charges what Play Console says); a Cashfree offer stores the amount, and that
 * amount is the only one its checkout will charge.
 */
@Entity({ name: 'personal_offer' })
@Index('IDX_personal_offer_user', ['userId', 'createdAt'])
export class PersonalOfferEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /// Opaque, >= 128 random bits, base64url. Unique in the database, not just by luck.
  @Column({ type: 'varchar', unique: true })
  code: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  tier: 'BASIC' | 'PRO';

  @Column({ type: 'varchar' })
  duration: '1M' | '3M' | '6M' | '12M';

  @Column({ type: 'varchar' })
  channel: OfferChannel;

  @Column({ type: 'varchar', nullable: true })
  playProductId: string | null;

  @Column({ type: 'varchar', nullable: true })
  playBasePlanId: string | null;

  @Column({ type: 'varchar', nullable: true })
  playOfferId: string | null;

  /// Integer paise (rule 3). Cashfree only; checked against the plan's normal price on creation.
  @Column({ type: 'bigint', nullable: true })
  amountPaise: string | null;

  /// The admin's own label. Shown in the dashboard, never to the person.
  @Column({ type: 'varchar', length: 200, nullable: true })
  note: string | null;

  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  /// Set when the payment is confirmed (verified webhook or Play verify), never at checkout.
  @Column({ type: 'timestamptz', nullable: true })
  usedAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  revokedAt: Date | null;

  @Column({ type: 'int' })
  createdByUserId: number;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
