import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { MEAL_SLOTS } from '../../logs/dto/log-food.dto';
import { RECIPE_LIMITS } from '../recipe-rules';

export class RecipeIngredientDto {
  @ApiProperty()
  @IsUUID()
  food_id: string;

  @ApiProperty({ example: 150 })
  @IsNumber()
  grams: number;
}

/// `POST /admin/recipes`. Shape only here; `recipeProblems` decides what a complete recipe is, so
/// every problem comes back at once instead of the first one class-validator meets.
export class RecipeDraftDto {
  @ApiProperty({ example: 'Moong dal chilla' })
  @IsString()
  name: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  name_hi?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty({ type: [String] })
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(RECIPE_LIMITS.maxSteps)
  steps: string[];

  @ApiProperty({ type: [String], enum: MEAL_SLOTS })
  @IsArray()
  @IsString({ each: true })
  slots: string[];

  @ApiProperty({ example: 2 })
  @IsInt()
  servings: number;

  @ApiProperty({ type: [RecipeIngredientDto] })
  @IsArray()
  @ArrayMaxSize(RECIPE_LIMITS.maxIngredients)
  @ValidateNested({ each: true })
  @Type(() => RecipeIngredientDto)
  ingredients: RecipeIngredientDto[];
}

/// `POST /recipes/{id}/log`: which meal, and how many servings.
export class LogRecipeDto {
  @ApiProperty({ example: 'lunch', enum: MEAL_SLOTS })
  @IsIn([...MEAL_SLOTS])
  slot: string;

  @ApiProperty({ example: 1 })
  @IsNumber()
  @Min(0.25)
  @Max(RECIPE_LIMITS.maxServings)
  servings: number;
}
