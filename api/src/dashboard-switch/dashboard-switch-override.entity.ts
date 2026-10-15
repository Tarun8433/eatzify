import { Column, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';

/// D-269. One person's dashboard switch, set by an admin regardless of the app-wide setting.
@Entity({ name: 'dashboard_switch_override' })
export class DashboardSwitchOverrideEntity {
  @PrimaryColumn({ type: 'integer' })
  userId: number;

  @Column({ type: 'boolean' })
  allowed: boolean;

  @Column({ type: 'integer' })
  updatedByUserId: number;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
