import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Max,
  Min,
} from 'class-validator';
import { GOAL_DECLARED } from '../onboarding-vocabulary';

const TIME_OF_DAY = /^([01]\d|2[0-3]):[0-5]\d$/;

const SEX = ['male', 'female', 'intersex_prefer_not_say'];
const GOAL = ['fat_loss', 'muscle_gain', 'maintenance'];
const ACTIVITY = ['sedentary', 'light', 'moderate', 'heavy'];
const FOOD_PREFERENCE = ['veg', 'non_veg', 'eggetarian', 'jain', 'vegan'];
const MEAL_COUNT = ['3', '4', '5_6'];
const LIFESTYLE = ['office', 'student', 'night_shift', 'flexible', 'home'];
const BUDGET = ['low', 'medium', 'premium'];

/// `PATCH /profile`. Every field optional; an omitted field carries forward. Bounds match
/// docs/03 §2 and the onboarding DTO — an edit must not be a way around the input rules.
export class PatchProfileDto {
  @ApiPropertyOptional({ example: 32 })
  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(99)
  age_years?: number;

  @ApiPropertyOptional({ example: 172 })
  @IsOptional()
  @IsInt()
  @Min(120)
  @Max(220)
  height_cm?: number;

  @ApiPropertyOptional({ example: 74.5 })
  @IsOptional()
  @IsNumber()
  @Min(30)
  @Max(250)
  weight_kg?: number;

  @ApiPropertyOptional({ example: 68 })
  @IsOptional()
  @IsNumber()
  @Min(30)
  @Max(250)
  goal_weight_kg?: number;

  @ApiPropertyOptional({ example: 'female' })
  @IsOptional()
  @IsIn(SEX)
  sex_at_birth?: string;

  @ApiPropertyOptional({ example: 'fat_loss' })
  @IsOptional()
  @IsIn(GOAL)
  goal?: string;

  @ApiPropertyOptional({ example: 'moderate' })
  @IsOptional()
  @IsIn(ACTIVITY)
  activity?: string;

  @ApiPropertyOptional({ example: 'veg' })
  @IsOptional()
  @IsIn(FOOD_PREFERENCE)
  food_preference?: string;

  @ApiPropertyOptional({ example: '3' })
  @IsOptional()
  @IsIn(MEAL_COUNT)
  meal_count?: string;

  @ApiPropertyOptional({ example: 'office' })
  @IsOptional()
  @IsIn(LIFESTYLE)
  lifestyle?: string;

  @ApiPropertyOptional({ example: 'medium' })
  @IsOptional()
  @IsIn(BUDGET)
  budget_tier?: string;

  @ApiPropertyOptional({ example: 'Priya' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

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

  @ApiPropertyOptional({ example: 'karela, no onion' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  food_dislikes?: string;

  @ApiPropertyOptional({ example: 8000 })
  @IsOptional()
  @IsInt()
  @Min(2000)
  @Max(18000)
  budget_monthly_inr?: number;
}
