import {
  BaseEntity,
  Column,
  Entity,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/// D-242. One MET value (or the per-set time cap) with the Compendium code it came from. Admin-editable
/// data — API rule 1 keeps these numbers out of `src/`. Extends BaseEntity for AdminJS, like FoodEntity.
@Entity({ name: 'energy_reference' })
export class EnergyReferenceEntity extends BaseEntity {
  @PrimaryColumn({ type: 'varchar' })
  key: string;

  @Column({ type: 'varchar' })
  activity: string;

  @Column({ type: 'numeric', precision: 5, scale: 2 })
  value: string;

  /// 'MET' for an intensity, 'min' for the per-set time cap.
  @Column({ type: 'varchar' })
  unit: string;

  /// Speed bands: a set is priced by the highest band at or below its speed. Null means any speed.
  @Column({ type: 'numeric', precision: 4, scale: 1, nullable: true })
  minSpeedKmh: string | null;

  @Column({ type: 'varchar' })
  source: string;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
