import { ApiProperty, ApiPropertyOptional, PickType } from '@nestjs/swagger';
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

/// `barcode` and `plan_tick` (docs/08 §8) join when something writes them.
export const LOG_SOURCES = ['manual', 'photo'] as const;
export type LogSource = (typeof LOG_SOURCES)[number];

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

  /// How the entry was chosen (docs/08 §8). `photo` means the user confirmed a scan's match (D-238);
  /// the nutrition is still the food row's, never the model's.
  @ApiPropertyOptional({ example: 'photo', enum: LOG_SOURCES })
  @IsOptional()
  @IsIn([...LOG_SOURCES])
  source?: LogSource;
}

/// "What would this portion give me?" — the add sheet's preview (D-238). The same quantity fields
/// as a log, so the preview and the entry it becomes are scaled by the same code.
export class PreviewFoodDto extends PickType(LogFoodDto, [
  'quantity_g',
  'measure',
  'measure_count',
] as const) {
  @ApiProperty({ example: '3f1c…' })
  @IsUUID()
  food_id: string;
}
