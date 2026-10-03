import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export const ANNOUNCEMENT_PRIORITIES = [
  'normal',
  'important',
  'critical',
] as const;
export type AnnouncementPriority = (typeof ANNOUNCEMENT_PRIORITIES)[number];
export const ANNOUNCEMENT_AUDIENCES = ['all', 'free', 'paid'] as const;
export type AnnouncementAudience = (typeof ANNOUNCEMENT_AUDIENCES)[number];
export type AnnouncementStatus = 'draft' | 'published' | 'archived';

/// In-app news and "important update" banners (admin panel plan, Phase C). Shown on the app's
/// home screen while published and inside its window.
@Entity({ name: 'announcement' })
export class AnnouncementEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 120 })
  title: string;

  @Column({ type: 'varchar', length: 2000 })
  body: string;

  @Column({ type: 'varchar', length: 500, nullable: true })
  imageUrl: string | null;

  @Column({ type: 'varchar', default: 'normal' })
  priority: AnnouncementPriority;

  @Column({ type: 'varchar', default: 'all' })
  audience: AnnouncementAudience;

  @Column({ type: 'varchar', default: 'draft' })
  status: AnnouncementStatus;

  @Column({ type: 'timestamptz' })
  startsAt: Date;

  @Column({ type: 'timestamptz', nullable: true })
  endsAt: Date | null;

  @Column()
  createdBy: number;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
