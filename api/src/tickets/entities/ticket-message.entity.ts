import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/// One message in a support conversation.
///
/// `fromSupport` is stored rather than worked out from the sender's role: roles change, and a reply
/// written by somebody who was an admin last year is still a reply from support.
@Entity({ name: 'ticket_message' })
@Index(['ticketId', 'createdAt'])
export class TicketMessageEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  ticketId: string;

  @Column()
  senderUserId: number;

  @Column({ type: 'boolean', default: false })
  fromSupport: boolean;

  @Column({ type: 'text' })
  body: string;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
