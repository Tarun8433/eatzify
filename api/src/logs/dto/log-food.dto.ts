import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
} from 'class-validator';

/// Slots come from the rule pack's meal splits (`config/rule-packs/v1.0.0.yaml`).
export const MEAL_SLOTS = [
  'breakfast',
  'mid_morning',
  'lunch',
  'snack',
  'evening',
  'dinner',
  'bedtime',
] as const;

export class LogFoodDto {
  @ApiProperty({ example: 'lunch', enum: MEAL_SLOTS })
  @IsIn([...MEAL_SLOTS])
  slot: string;

  @ApiPropertyOptional({ example: '3f1c…' })
  @IsOptional()
  @IsUUID()
  food_id?: string;

  /// For something not in the database. docs/09 §5 allows a custom entry rather than forcing the
  /// user to abandon the log.
  @ApiPropertyOptional({ example: 'Aunty ka halwa' })
  @IsOptional()
  @IsString()
  custom_name?: string;

  @ApiPropertyOptional({ example: 150 })
  @IsOptional()
  @IsNumber()
  @Min(1)
  quantity_g?: number;

  /// A household measure label plus how many, e.g. 2 × "katori". docs/03 §units: the measure is
  /// primary and grams secondary, so the client sends what the user actually chose.
  @ApiPropertyOptional({ example: 'katori' })
  @IsOptional()
  @IsString()
  measure?: string;

  @ApiPropertyOptional({ example: 2 })
  @IsOptional()
  @IsNumber()
  @Min(0.25)
  measure_count?: number;

  // --- custom-entry nutrition, per the whole entry (not per 100 g) ---
  @ApiPropertyOptional({ example: 250 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  kcal?: number;

  @ApiPropertyOptional({ example: 6 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  protein_g?: number;

  @ApiPropertyOptional({ example: 30 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  carb_g?: number;

  @ApiPropertyOptional({ example: 10 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  fat_g?: number;
}
