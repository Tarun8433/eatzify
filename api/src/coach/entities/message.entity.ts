import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/// One message between a coach and a client (docs/02 FR-5.5, docs/09 §6).
///
/// The THREAD is the pair, not a row of its own: a coach and a client have exactly one
/// conversation, and a table of threads would only ever hold what these two columns already say.
///
/// docs/13 §6 puts messages under the retention table — they are about somebody's eating, so they
/// are health data by any honest reading and live under the same grant as everything else.
@Entity({ name: 'message' })
@Index(['coachUserId', 'clientUserId', 'createdAt'])
export class MessageEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  coachUserId: number;

  @Column()
  clientUserId: number;

  /// Which of the two wrote it. Stored rather than derived, because "who said this" must survive
  /// a coach later becoming a client of somebody else.
  @Column()
  senderUserId: number;

  @Column({ type: 'text' })
  body: string;

  /// When the OTHER side read it. Null until then.
  @Column({ type: 'timestamptz', nullable: true })
  readAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
