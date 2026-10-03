import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';
import type { ContentClass } from '../../notifications/entities/notification.entity';

export const CHANNELS = ['in_app', 'email', 'push', 'sms', 'whatsapp'] as const;
export type Channel = (typeof CHANNELS)[number];
export type CampaignStatus =
  'scheduled' | 'sending' | 'sent' | 'failed' | 'cancelled';

/// Who a campaign is for. The same filters the existing broadcast understands, plus the account
/// state (admin panel plan, Phase C).
export type CampaignSegment = {
  tier?: string;
  goal?: string;
  conditions?: string[];
  inactive_days?: number;
  user_ids?: number[];
  account_state?: 'active' | 'unverified';
};

export type ChannelResult = { sent: number; failed: number };

/// Admin panel plan, Phase C: one message to an audience, now or later, with what each channel did.
@Entity({ name: 'notification_campaign' })
export class NotificationCampaignEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 120 })
  title: string;

  @Column({ type: 'varchar', length: 1000 })
  body: string;

  @Column({ type: 'varchar' })
  contentClass: ContentClass;

  @Column({ type: 'jsonb', default: {} })
  segment: CampaignSegment;

  @Column({ type: 'text', array: true })
  channels: Channel[];

  @Column({ type: 'varchar', default: 'scheduled' })
  status: CampaignStatus;

  @Column({ type: 'timestamptz' })
  scheduledAt: Date;

  @Column({ type: 'timestamptz', nullable: true })
  sentAt: Date | null;

  /// How many people the segment matched when it went out.
  @Column({ type: 'int', nullable: true })
  audience: number | null;

  @Column({ type: 'jsonb', default: {} })
  results: Partial<Record<Channel, ChannelResult>>;

  @Column({ type: 'varchar', length: 500, nullable: true })
  error: string | null;

  @Column()
  createdBy: number;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
