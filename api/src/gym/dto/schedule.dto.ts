import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { BODY_FIGURES, EFFORT_SCALES } from '../gym-types';

export class ScheduleDto {
  /// ISO weekday ('1' Monday … '7' Sunday) → routine id, or null for rest. Checked in the service.
  @ApiProperty({ example: { '1': 12, '3': 13, '5': 14 } })
  @IsObject()
  week: Record<string, number | null>;
}

export class DayOverrideDto {
  /// A diary date the server itself sent in `week_days` or the calendar.
  @ApiProperty({ example: '2026-09-21' })
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  date: string;

  @ApiPropertyOptional({ example: 13 })
  @IsOptional()
  @IsInt()
  routine_id?: number | null;

  /// true: rest that day. false/absent with no routine: back to the weekly plan.
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  rest?: boolean;
}

export class GymSettingsDto {
  @IsOptional() @IsInt() @Min(15) @Max(600) rest_sec?: number;
  @IsOptional() @IsIn([...EFFORT_SCALES]) effort_scale?: string;
  @IsOptional() @IsBoolean() keep_awake?: boolean;
  @IsOptional() @IsBoolean() sound?: boolean;
  @IsOptional() @IsIn([...BODY_FIGURES]) body_figure?: string;
}
