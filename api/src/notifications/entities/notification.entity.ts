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

/// docs/13 §5. Every notification says what KIND of message it is, because the targeting rules
/// differ: only a clinical one may be aimed at people by health condition, and a commercial one
/// never may.
export const CONTENT_CLASSES = ['clinical', 'service', 'commercial'] as const;
export type ContentClass = (typeof CONTENT_CLASSES)[number];

/// One message to one person, kept so the app can show a list rather than a toast that is gone
/// before it is read (docs/14 §6). The renewal notices docs/11 §8 requires are rows here.
@Entity({ name: 'notification' })
@Index(['userId', 'createdAt'])
export class NotificationEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  /// What produced it — `renewal_t7`, `trial_ending`, `admin_broadcast`. Never shown raw.
  @Column({ type: 'varchar' })
  kind: string;

  @Column({ type: 'varchar' })
  contentClass: ContentClass;

  @Column({ type: 'text' })
  title: string;

  @Column({ type: 'text' })
  body: string;

  /// What the app needs to act on it — a tier, an amount, a screen to open.
  @Column({ type: 'jsonb', nullable: true })
  data: Record<string, unknown> | null;

  /// The one-per-thing key. A renewal sweep that runs twice must not send two T-7 notices, and a
  /// unique index is the only version of that rule a second server cannot race.
  @Column({ type: 'varchar', nullable: true })
  dedupeKey: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  readAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
