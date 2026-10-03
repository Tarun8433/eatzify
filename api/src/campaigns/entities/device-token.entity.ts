import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

/// Where a push notification goes: one app install (admin panel plan, Phase C).
@Entity({ name: 'device_token' })
export class DeviceTokenEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar', length: 512, unique: true })
  token: string;

  @Column({ type: 'varchar' })
  platform: 'android' | 'ios';

  @Column({ type: 'timestamptz', default: () => 'now()' })
  lastSeenAt: Date;
}
