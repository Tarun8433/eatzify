import {
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

/// docs/11 §5. One row per user; the lifecycle moves through it rather than creating a row per
/// state, so "what is this person entitled to right now" is a single lookup.
@Entity({ name: 'subscription' })
export class SubscriptionEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Index({ unique: true })
  @Column()
  userId: number;

  @Column({ type: 'varchar', default: 'FREE' })
  tier: string;

  @Column({ type: 'varchar', default: 'active' })
  status: string;

  /// Null for FREE, which never expires.
  @Column({ type: 'timestamptz', nullable: true })
  currentPeriodEnd: Date | null;

  /// Provider-side id, so a webhook can find this row. Null until a real purchase happens.
  @Column({ type: 'varchar', nullable: true })
  providerRef: string | null;

  @Column({ type: 'varchar', nullable: true })
  provider: string | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
