import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsISO8601, IsNumber, IsOptional } from 'class-validator';
import {
  MEASUREMENT_KINDS,
  MEASUREMENT_SOURCES,
  MEASUREMENT_UNITS,
} from '../measurement-rules';

export class CreateMeasurementDto {
  @ApiProperty({ example: 'weight', enum: MEASUREMENT_KINDS })
  @IsIn([...MEASUREMENT_KINDS])
  kind: string;

  @ApiProperty({ example: 74.5 })
  @IsNumber()
  value: number;

  /// Whether it is the RIGHT unit for the kind is checked in the service — a closed list here only
  /// says the string is one the app understands.
  @ApiProperty({ example: 'kg', enum: MEASUREMENT_UNITS })
  @IsIn(MEASUREMENT_UNITS)
  unit: string;

  /// Optional. The server derives the diary day from it, or from now — CLAUDE.md rule 8 means the
  /// client never decides which day a reading belongs to.
  @ApiPropertyOptional({ example: '2026-08-25T09:30:00Z' })
  @IsOptional()
  @IsISO8601()
  recorded_at?: string;

  /// Where the number came from. Absent means a person typed it, which is both the safe default
  /// and what every existing client sends.
  @ApiPropertyOptional({ example: 'manual', enum: MEASUREMENT_SOURCES })
  @IsOptional()
  @IsIn([...MEASUREMENT_SOURCES])
  source?: string;
}
