import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

/// The dataset's ten body parts. A custom exercise picks one so it can be filtered and drawn.
export const BODY_PARTS = [
  'back',
  'cardio',
  'chest',
  'lower arms',
  'lower legs',
  'neck',
  'shoulders',
  'upper arms',
  'upper legs',
  'waist',
] as const;

export class CreateExerciseDto {
  @ApiProperty({ example: 'Landmine press' })
  @IsString()
  @Length(1, 60)
  name: string;

  @ApiProperty({ example: 'shoulders', enum: BODY_PARTS })
  @IsIn([...BODY_PARTS])
  body_part: string;

  @ApiPropertyOptional({
    example: 'One end of a barbell in a corner, press it up and forward.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string | null;
}

export class UpdateExerciseDto extends PartialType(CreateExerciseDto) {}
