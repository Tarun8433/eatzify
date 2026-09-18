import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  PrimaryColumn,
} from 'typeorm';

/// docs/11 §6: "max 1 trial per phone hash lifetime". Keyed on the number rather than the device,
/// because devices are shared and device-keyed trials punish families — and keyed on a HASH,
/// because the only question this table answers is "has this number had one".
///
/// It outlives the account that used it on purpose: deleting an account must not hand out a second
/// trial, so `userId` goes null while the row stays.
@Entity({ name: 'trial_grant' })
export class TrialGrantEntity extends BaseEntity {
  @PrimaryColumn({ type: 'varchar' })
  phoneHash: string;

  @Column({ type: 'integer', nullable: true })
  userId: number | null;

  @Column({ type: 'varchar' })
  tier: string;

  @CreateDateColumn({ type: 'timestamptz' })
  grantedAt: Date;
}
