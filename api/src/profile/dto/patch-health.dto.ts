import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsArray,
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import {
  ALLERGIES,
  CONDITIONS,
  DIGESTIVE_SYMPTOMS,
  INJURY_AREAS,
  MENSTRUAL_REGULARITY,
} from '../onboarding-vocabulary';

/// `PATCH /profile/health` (docs/09 §4). Every field optional — an omitted field carries forward
/// from the current version rather than being cleared, so a partial edit cannot silently drop a
/// declared condition.
export class PatchHealthDto {
  @ApiPropertyOptional({
    example: ['prediabetes'],
    type: [String],
    enum: CONDITIONS,
  })
  @IsOptional()
  @IsArray()
  @IsIn([...CONDITIONS], { each: true })
  conditions?: string[];

  @ApiPropertyOptional({ example: ['peanut'], type: [String], enum: ALLERGIES })
  @IsOptional()
  @IsArray()
  @IsIn([...ALLERGIES], { each: true })
  allergies?: string[];

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

  @ApiPropertyOptional({ example: 'Metformin 500mg' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
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
