import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import type { LogEntryView } from '../logs/logs.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import { LogRecipeDto } from './dto/recipe.dto';
import { RecipesService, type RecipeView } from './recipes.service';

/// D-263: the Plan tab's recipes. Published ones only. The filters are a food preference and a
/// meal name — no health data, so a query string is fine (api rule 6).
@ApiTags('Recipes')
@ApiBearerAuth()
@Controller({ path: 'recipes', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class RecipesController {
  constructor(private readonly service: RecipesService) {}

  /// Narrowed to the caller's own food preference unless the app asks for another.
  @Get()
  async list(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Query('suitable_for') suitableFor?: string,
    @Query('slot') slot?: string,
  ): Promise<RecipeView[]> {
    const preference =
      suitableFor ?? (await this.service.preferenceOf(Number(request.user.id)));
    return this.service.listPublished({
      suitableFor: preference ?? undefined,
      slot,
    });
  }

  @Get(':id')
  one(@Param('id', ParseUUIDPipe) id: string): Promise<RecipeView> {
    return this.service.getPublished(id);
  }

  /// One diary entry per ingredient, scaled to the servings eaten.
  @Post(':id/log')
  @HttpCode(HttpStatus.CREATED)
  log(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: LogRecipeDto,
  ): Promise<LogEntryView[]> {
    return this.service.log(
      Number(request.user.id),
      id,
      dto.slot,
      dto.servings,
    );
  }
}
