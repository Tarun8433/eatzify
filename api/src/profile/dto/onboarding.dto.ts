import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import {
  ALLERGIES,
  CONDITIONS,
  DIGESTIVE_SYMPTOMS,
  GOAL_DECLARED,
  INJURY_AREAS,
  MENSTRUAL_REGULARITY,
} from '../onboarding-vocabulary';

/// Legal values are docs/03 §2. Kept as literal lists so an unknown enum is a 422 at the boundary
/// rather than a bad row in the database.
const SEX = ['male', 'female', 'intersex_prefer_not_say'];
const GOAL = ['fat_loss', 'muscle_gain', 'maintenance'];
const ACTIVITY = ['sedentary', 'light', 'moderate', 'heavy'];
const FOOD_PREFERENCE = ['veg', 'non_veg', 'eggetarian', 'jain', 'vegan'];
const MEAL_COUNT = ['3', '4', '5_6'];
const LIFESTYLE = ['office', 'student', 'night_shift', 'flexible', 'home'];
const BUDGET = ['low', 'medium', 'premium'];

/// 24-hour "HH:MM". Stored as text rather than a timestamp: a wake-up time is a time of day, not an
/// instant, and putting it in a timestamptz makes it drift with the date it was attached to.
const TIME_OF_DAY = /^([01]\d|2[0-3]):[0-5]\d$/;

/// Free text the user typed. Capped so a paste cannot become a storage problem, and never parsed —
/// "no onion" is for a human to read.
const FREE_TEXT_MAX = 500;

export class ProfileInputDto {
  @ApiProperty({ example: 32 })
  @IsInt()
  @Min(18)
  @Max(99)
  age_years: number;

  @ApiProperty({ example: 172 })
  @IsInt()
  @Min(120)
  @Max(220)
  height_cm: number;

  @ApiProperty({ example: 74.5 })
  @IsNumber()
  @Min(30)
  @Max(250)
  weight_kg: number;

  @ApiPropertyOptional({ example: 68 })
  @IsOptional()
  @IsNumber()
  @Min(30)
  @Max(250)
  goal_weight_kg?: number;

  @ApiProperty({ example: 'female' })
  @IsIn(SEX)
  sex_at_birth: string;

  @ApiProperty({ example: 'fat_loss' })
  @IsIn(GOAL)
  goal: string;

  @ApiProperty({ example: 'moderate' })
  @IsIn(ACTIVITY)
  activity: string;

  @ApiProperty({ example: 'veg' })
  @IsIn(FOOD_PREFERENCE)
  food_preference: string;

  @ApiProperty({ example: '3' })
  @IsIn(MEAL_COUNT)
  meal_count: string;

  @ApiProperty({ example: 'office' })
  @IsIn(LIFESTYLE)
  lifestyle: string;

  @ApiProperty({ example: 'medium' })
  @IsIn(BUDGET)
  budget_tier: string;

  @ApiPropertyOptional({ example: 'Priya' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

  /// The user's own words for their goal. `goal` above stays the engine's input.
  @ApiPropertyOptional({ example: 'weight_loss', enum: GOAL_DECLARED })
  @IsOptional()
  @IsIn([...GOAL_DECLARED])
  goal_declared?: string;

  @ApiPropertyOptional({ example: '06:30' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  wake_time?: string;

  @ApiPropertyOptional({ example: '23:00' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  sleep_time?: string;

  /// Asked directly rather than derived from wake/sleep: someone who is in bed at 23:00 and up at
  /// 06:30 has not necessarily slept seven hours, and the difference is the clinically useful part.
  @ApiPropertyOptional({ example: 7 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(24)
  sleep_hours?: number;

  @ApiPropertyOptional({ example: '07:30' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  breakfast_time?: string;

  @ApiPropertyOptional({ example: '13:00' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  lunch_time?: string;

  @ApiPropertyOptional({ example: '17:30' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  evening_snack_time?: string;

  @ApiPropertyOptional({ example: '20:30' })
  @IsOptional()
  @Matches(TIME_OF_DAY)
  dinner_time?: string;

  /// Dislikes, not allergies. Keeping them apart matters: an allergy is a hard exclusion the engine
  /// must never violate, a dislike is a preference it should respect where it can.
  @ApiPropertyOptional({ example: 'karela, no onion' })
  @IsOptional()
  @IsString()
  @MaxLength(FREE_TEXT_MAX)
  food_dislikes?: string;

  /// Rupees a month (D-78). `budget_tier` above is derived from it by the app and stays what the
  /// engine plans on; this is the figure a coach sees and what a later rule pack could price
  /// against. Bounds match the slider, so a hand-rolled request cannot store a budget the app
  /// could not have produced.
  @ApiPropertyOptional({ example: 8000 })
  @IsOptional()
  @IsInt()
  @Min(2000)
  @Max(18000)
  budget_monthly_inr?: number;
}

export class HealthProfileInputDto {
  /// Constrained to the closed list: an unknown condition is a 422 at the boundary, not a row in
  /// the database nobody can interpret later.
  @ApiProperty({ example: ['prediabetes'], type: [String], enum: CONDITIONS })
  @IsArray()
  @IsIn([...CONDITIONS], { each: true })
  conditions: string[];

  @ApiProperty({ example: ['peanut'], type: [String], enum: ALLERGIES })
  @IsArray()
  @IsIn([...ALLERGIES], { each: true })
  allergies: string[];

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  screened_special_diet?: boolean;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  screened_insulin_or_kidney?: boolean;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  screened_eating_disorder?: boolean;

  /// Free text on purpose. A structured drug list needs a drug database and an interaction check we
  /// do not have; a coach reading "metformin 500 twice daily" is worth more than a wrong ontology.
  @ApiPropertyOptional({ example: 'Metformin 500mg, vitamin D' })
  @IsOptional()
  @IsString()
  @MaxLength(FREE_TEXT_MAX)
  medications?: string;

  @ApiPropertyOptional({
    example: ['acidity'],
    type: [String],
    enum: DIGESTIVE_SYMPTOMS,
  })
  @IsOptional()
  @IsArray()
  @IsIn([...DIGESTIVE_SYMPTOMS], { each: true })
  digestive_symptoms?: string[];

  @ApiPropertyOptional({
    example: ['knee_pain'],
    type: [String],
    enum: INJURY_AREAS,
  })
  @IsOptional()
  @IsArray()
  @IsIn([...INJURY_AREAS], { each: true })
  injuries?: string[];

  /// FR-1.3: only sent for `sex_at_birth === 'female'`. The app does not ask otherwise and the
  /// service refuses to store them otherwise, so a crafted request cannot seed the column either.
  @ApiPropertyOptional({ example: 'regular', enum: MENSTRUAL_REGULARITY })
  @IsOptional()
  @IsIn([...MENSTRUAL_REGULARITY])
  menstrual_regularity?: string;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  pregnant_or_breastfeeding?: boolean;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  heavy_bleeding_or_pain?: boolean;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  hormonal_medication?: boolean;
}

export class ConsentInputDto {
  @ApiProperty({ example: 'health_data_storage' })
  @IsIn(['health_data_storage', 'plan_generation', 'marketing'])
  type: string;

  @ApiProperty({ example: true })
  @IsBoolean()
  granted: boolean;
}

export class OnboardingDto {
  @ApiProperty({ type: ProfileInputDto })
  @ValidateNested()
  @Type(() => ProfileInputDto)
  profile: ProfileInputDto;

  @ApiProperty({ type: HealthProfileInputDto })
  @ValidateNested()
  @Type(() => HealthProfileInputDto)
  health_profile: HealthProfileInputDto;

  @ApiProperty({ type: [ConsentInputDto] })
  @IsArray()
  @ArrayNotEmpty()
  @ValidateNested({ each: true })
  @Type(() => ConsentInputDto)
  consents: ConsentInputDto[];
}
