import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { FoodEntity } from '../../foods/entities/food.entity';

/// The same review lifecycle as a food (docs/08 §4, D-227): a recipe's numbers reach a person's
/// diary, so nothing published itself.
export const RECIPE_STATUSES = [
  'draft',
  'reviewed',
  'published',
  'retired',
] as const;
export type RecipeStatus = (typeof RECIPE_STATUSES)[number];

/// A dish made of foods (D-263). It carries no nutrition of its own: every figure is derived from
/// its ingredients' food rows, so correcting a food corrects every recipe that uses it.
@Entity({ name: 'recipe' })
export class RecipeEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ type: 'varchar' })
  name: string;

  @Column({ type: 'varchar', nullable: true })
  nameHi: string | null;

  @Column({ type: 'text', default: '' })
  description: string;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  steps: string[];

  /// Which meals it suits — `MEAL_SLOTS`.
  @Column({ type: 'text', array: true })
  slots: string[];

  /// How many servings the ingredient grams make.
  @Column({ type: 'integer' })
  servings: number;

  @Column({ type: 'varchar', default: 'draft' })
  status: RecipeStatus;

  @Column({ type: 'integer', nullable: true })
  createdByUserId: number | null;

  @Column({ type: 'integer', nullable: true })
  reviewedByUserId: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  reviewedAt: Date | null;

  @Column({ type: 'integer', nullable: true })
  publishedByUserId: number | null;

  @Column({ type: 'timestamptz', nullable: true })
  publishedAt: Date | null;

  @OneToMany(() => RecipeIngredientEntity, (i) => i.recipe, { cascade: true })
  ingredients: RecipeIngredientEntity[];

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}

/// One food in a recipe, in grams for the WHOLE recipe.
@Entity({ name: 'recipe_ingredient' })
export class RecipeIngredientEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  recipeId: string;

  @ManyToOne(() => RecipeEntity, (r) => r.ingredients, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'recipeId' })
  recipe: RecipeEntity;

  @Column({ type: 'uuid' })
  foodId: string;

  @ManyToOne(() => FoodEntity, { onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'foodId' })
  food: FoodEntity;

  @Column({ type: 'numeric', precision: 7, scale: 1 })
  grams: string;

  /// The order the admin listed them in.
  @Column({ type: 'integer' })
  position: number;
}
