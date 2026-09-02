import {
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { FoodEntity } from './food.entity';

/// docs/03 §1: `1 katori = 150 g`. Marked "non-negotiable for India" because users think in
/// katoris, not grams — docs/03 §units makes the household measure PRIMARY and grams secondary.
@Entity({ name: 'household_measure' })
@Index(['foodId', 'label'], { unique: true })
export class HouseholdMeasureEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => FoodEntity, (f) => f.measures, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'foodId' })
  food: FoodEntity;

  @Column({ type: 'uuid' })
  foodId: string;

  /// e.g. "katori", "roti", "glass". Shown to the user, so it goes through l10n on the client.
  @Column({ type: 'varchar' })
  label: string;

  @Column({ type: 'varchar', nullable: true })
  labelHi: string | null;

  @Column({ type: 'numeric', precision: 7, scale: 2 })
  grams: string;

  /// The measure offered by default when logging this food.
  @Column({ type: 'boolean', default: false })
  isDefault: boolean;
}
