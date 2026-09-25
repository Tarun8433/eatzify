import {
  BaseEntity,
  Column,
  Entity,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';
import type { Tier } from '../../billing/tiers';

/// D-238. Who may scan a meal photo, per tier — edited by an admin, read on every scan.
@Entity({ name: 'scan_policy' })
export class ScanPolicyEntity extends BaseEntity {
  @PrimaryColumn({ type: 'varchar' })
  tier: Tier;

  @Column({ type: 'boolean' })
  enabled: boolean;

  /// Scans per diary day (the 04:00 IST day, `diaryDateFor`).
  @Column({ type: 'integer' })
  dailyLimit: number;

  /// A rewarded ad must be watched before each scan.
  @Column({ type: 'boolean' })
  requiresAd: boolean;

  /// Days after signup this tier may scan at all; null is no window.
  @Column({ type: 'integer', nullable: true })
  trialDays: number | null;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
