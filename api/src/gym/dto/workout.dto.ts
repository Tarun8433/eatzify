import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { EXERCISE_MODES } from '../gym-types';
import { RoutineExerciseDto } from './routine.dto';

export const MAX_WORKOUT_ENTRIES = 60;
export const MAX_ENTRY_SETS = 30;

export class WorkoutSetDto {
  @IsOptional() @IsNumber() @Min(0) @Max(500) weight_kg?: number | null;
  @IsOptional() @IsInt() @Min(0) @Max(500) reps?: number | null;
  @IsOptional() @IsInt() @Min(0) @Max(3600) seconds?: number | null;
  @IsOptional() @IsNumber() @Min(0) @Max(600) minutes?: number | null;
  @IsOptional() @IsNumber() @Min(0) @Max(40) speed_kmh?: number | null;
  @IsBoolean() done: boolean;
  @IsOptional() @IsNumber() @Min(0) @Max(10) rir?: number | null;
  @IsOptional() @IsNumber() @Min(6) @Max(10) rpe?: number | null;
}

export class WorkoutEntryDto {
  @ApiProperty({ example: '0025' })
  @IsString()
  @Length(1, 40)
  exercise_id: string;

  @IsIn([...EXERCISE_MODES])
  mode: (typeof EXERCISE_MODES)[number];

  @IsOptional()
  @ValidateNested()
  @Type(() => RoutineExerciseDto)
  target?: RoutineExerciseDto | null;

  @IsArray()
  @ArrayMaxSize(MAX_ENTRY_SETS)
  @ValidateNested({ each: true })
  @Type(() => WorkoutSetDto)
  sets: WorkoutSetDto[];

  @IsOptional() @IsNumber() @Min(0) @Max(500) top_weight_kg?: number | null;
  @IsOptional() @IsString() @MaxLength(40) superset?: string | null;
}

export class SaveWorkoutDto {
  /// Made by the phone when the workout starts, so a retried save lands once.
  @ApiProperty({ example: '6f1c2b1e-8a57-4e1b-9d6a-1c1f2d3e4f50' })
  @IsUUID()
  id: string;

  @ApiPropertyOptional({ example: 12 })
  @IsOptional()
  @IsInt()
  routine_id?: number | null;

  @ApiProperty({ example: 'Push Day' })
  @IsString()
  @Length(1, 80)
  name: string;

  @ApiProperty({ example: '2026-09-19T07:02:00Z' })
  @IsISO8601()
  started_at: string;

  @ApiProperty({ example: '2026-09-19T07:58:00Z' })
  @IsISO8601()
  ended_at: string;

  /// The weigh-in at the start, if the user gave one. It prices the energy estimate (D-242).
  @ApiPropertyOptional({ example: 74.5 })
  @IsOptional()
  @IsNumber()
  @Min(20)
  @Max(300)
  body_weight_kg?: number | null;

  @IsArray()
  @ArrayMaxSize(MAX_WORKOUT_ENTRIES)
  @ValidateNested({ each: true })
  @Type(() => WorkoutEntryDto)
  entries: WorkoutEntryDto[];
}
