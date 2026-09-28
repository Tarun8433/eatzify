import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { HouseholdMeasureEntity } from './household-measure.entity';

/// docs/03 §1: an atomic nutrition record **per 100 g edible portion**. Every quantity in the
/// system normalises to that, so a food row never carries a serving size — that is what
/// `household_measure` is for.
///
/// docs/08 §4's lifecycle. Nothing is deleted: a retired food is still in somebody's diary.
export const FOOD_STATUSES = [
  'draft',
  'reviewed',
  'published',
  'retired',
] as const;
export type FoodStatus = (typeof FOOD_STATUSES)[number];

/// `source` and `sourceRef` are not decoration: docs/03 says a food must be traceable to IFCT/INDB
/// or a named manual entry, because a nutrition number nobody can attribute cannot be corrected.
@Entity({ name: 'food' })
export class FoodEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ type: 'varchar' })
  name: string;

  /// Devanagari name. Users search in the language they cook in.
  @Column({ type: 'varchar', nullable: true })
  nameHi: string | null;

  /// What people actually type. "chapati" for roti, "maggi" for instant noodles, "golgappa" for
  /// pani puri. Search matches these as well as the names, because a food nobody can find is a
  /// food nobody logs — and an unlogged meal is a hole in the diary, not a neutral absence.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  aliases: string[];

  // --- per 100 g edible portion ---
  @Column({ type: 'numeric', precision: 7, scale: 2 })
  kcal: string;

  @Column({ type: 'numeric', precision: 6, scale: 2 })
  proteinG: string;

  @Column({ type: 'numeric', precision: 6, scale: 2 })
  fatG: string;

  @Column({ type: 'numeric', precision: 6, scale: 2 })
  carbG: string;

  @Column({ type: 'numeric', precision: 6, scale: 2, default: 0 })
  fibreG: string;

  @Column({ type: 'numeric', precision: 8, scale: 2, default: 0 })
  sodiumMg: string;

  @Column({ type: 'numeric', precision: 6, scale: 2, default: 0 })
  addedSugarG: string;

  @Column({ type: 'numeric', precision: 6, scale: 2, default: 0 })
  saturatedFatG: string;

  /// Namespaced tags — the rule pack matches on these exact strings (`gi:high`, `attr:root_veg`,
  /// `attr:high_fibre`). A typo here silently removes a food from a medical constraint, so the
  /// vocabulary is validated rather than free text.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  tags: string[];

  /// docs/03 §2 food preference. A food is legal for a preference if the preference is listed.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  suitableFor: string[];

  /// docs/03 §2 allergen set. Drives exclusion, so it must be exhaustive rather than best-effort.
  @Column({ type: 'text', array: true, default: () => "'{}'" })
  allergens: string[];

  @Column({ type: 'varchar', default: 'medium' })
  costTier: string;

  /// The photograph, and the credit it is served under (D-83). `imageAttribution` is a legal
  /// requirement for the CC BY and CC BY-SA images, not decoration — see the migration.
  @Column({ type: 'varchar', nullable: true })
  imageSlug: string | null;

  @Column({ type: 'varchar', nullable: true })
  imageLicense: string | null;

  @Column({ type: 'text', nullable: true })
  imageAttribution: string | null;

  @Column({ type: 'text', nullable: true })
  imageSourcePage: string | null;

  /// From the import manifest. Every image landed as NEEDS_REVIEW: nobody has confirmed the
  /// photograph shows the food it is filed under.
  @Column({ type: 'varchar', nullable: true })
  imageStatus: string | null;

  @Column({ type: 'varchar' })
  source: string;

  @Column({ type: 'varchar', nullable: true })
  sourceRef: string | null;

  /// Unverified rows are visible to admins and excluded from plan generation — a half-entered food
  /// must never reach a user's plan.
  ///
  /// Kept in step with [status] by `FoodsService`: published sets it, retired clears it. It is the
  /// flag every existing read still uses, and the expand half of the migration that adds a status
  /// (D-227).
  @Column({ type: 'boolean', default: false })
  isVerified: boolean;

  /// docs/08 §4: `draft` → `reviewed` → `published`, and `retired` for a row that must stop being
  /// offered without being deleted (it is in somebody's diary).
  @Column({ type: 'varchar', default: 'draft' })
  status: FoodStatus;

  /// Who checked it, and when. A food's macros end up in a plan, so "somebody reviewed this" has to
  /// name somebody (docs/02 FR-8.3's spirit, and why `coach_application.reviewedByUserId` exists).
  @Column({ type: 'integer', nullable: true })
  reviewedByUserId: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  reviewedAt: Date | null;

  @Column({ type: 'integer', nullable: true })
  publishedByUserId: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  publishedAt: Date | null;

  @OneToMany(() => HouseholdMeasureEntity, (m) => m.food)
  measures: HouseholdMeasureEntity[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
