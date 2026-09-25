import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import {
  EXERCISE_MODES,
  PROGRESSION_RULES,
  ROUTINE_ICONS,
  ROUTINE_RULES,
} from '../gym-types';

/// Bounds are sanity limits on what a person can type, not training advice.
export const MAX_ROUTINE_EXERCISES = 40;
export const MAX_SETS = 20;

export class RoutineExerciseDto {
  @ApiProperty({ example: '0025' })
  @IsString()
  @Length(1, 40)
  exercise_id: string;

  @ApiProperty({ enum: EXERCISE_MODES })
  @IsIn([...EXERCISE_MODES])
  mode: (typeof EXERCISE_MODES)[number];

  @ApiProperty({ example: 3 })
  @IsInt()
  @Min(1)
  @Max(MAX_SETS)
  sets: number;

  @IsOptional() @IsInt() @Min(1) @Max(200) reps?: number | null;
  @IsOptional() @IsNumber() @Min(0) @Max(500) weight_kg?: number | null;
  @IsOptional() @IsInt() @Min(1) @Max(3600) seconds?: number | null;
  @IsOptional() @IsNumber() @Min(0.5) @Max(600) minutes?: number | null;
  @IsOptional() @IsNumber() @Min(0) @Max(40) speed_kmh?: number | null;
  @IsOptional() @IsBoolean() bodyweight?: boolean | null;
  @IsOptional() @IsBoolean() per_side?: boolean | null;
  @IsOptional() @IsIn([...PROGRESSION_RULES]) progression?:
    (typeof PROGRESSION_RULES)[number] | null;
  @IsOptional() @IsNumber() @Min(0.25) @Max(50) increment?: number | null;
  @IsOptional() @IsInt() @Min(1) @Max(200) reps_min?: number | null;
  @IsOptional() @IsInt() @Min(1) @Max(200) reps_max?: number | null;
  @IsOptional() @IsString() @MaxLength(40) superset?: string | null;
}

export class RoutineDto {
  @ApiProperty({ example: 'Push Day' })
  @IsString()
  @Length(1, 60)
  name: string;

  @ApiPropertyOptional({ enum: ROUTINE_ICONS })
  @IsOptional()
  @IsIn([...ROUTINE_ICONS])
  icon?: string;

  @ApiPropertyOptional({ enum: ROUTINE_RULES })
  @IsOptional()
  @IsIn([...ROUTINE_RULES])
  progression?: string;

  @ApiProperty({ type: [RoutineExerciseDto] })
  @IsArray()
  @ArrayMaxSize(MAX_ROUTINE_EXERCISES)
  @ValidateNested({ each: true })
  @Type(() => RoutineExerciseDto)
  exercises: RoutineExerciseDto[];
}
