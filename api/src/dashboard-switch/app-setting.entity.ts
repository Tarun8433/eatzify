import { Column, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';

/// D-269. An app-wide setting an admin edits, one row per key. The value is JSON so a later setting
/// needs no migration of its own.
@Entity({ name: 'app_setting' })
export class AppSettingEntity {
  @PrimaryColumn({ type: 'varchar', length: 100 })
  key: string;

  @Column({ type: 'jsonb' })
  value: unknown;

  @Column({ type: 'integer', nullable: true })
  updatedByUserId: number | null;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
