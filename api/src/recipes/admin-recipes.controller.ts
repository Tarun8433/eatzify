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
import { Permit, PermissionsGuard } from '../admin/permissions.guard';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { RecipeDraftDto } from './dto/recipe.dto';
import { RECIPE_STATUSES, type RecipeStatus } from './entities/recipe.entity';
import { RecipesService, type RecipeView } from './recipes.service';

/// D-263: the admin panel's recipe queue — the food review's lifecycle, for dishes.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('content.manage')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin/recipes', version: '1' })
export class AdminRecipesController {
  constructor(private readonly recipes: RecipesService) {}

  @Get()
  byStatus(@Query('status') status?: string): Promise<RecipeView[]> {
    const wanted = (RECIPE_STATUSES as readonly string[]).includes(status ?? '')
      ? (status as RecipeStatus)
      : 'draft';
    return this.recipes.byStatus(wanted);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(
    @Body() dto: RecipeDraftDto,
    @Request() request: { user: JwtPayloadType },
  ): Promise<RecipeView> {
    return this.recipes.createDraft(
      {
        name: dto.name,
        nameHi: dto.name_hi ?? null,
        description: dto.description ?? '',
        steps: dto.steps,
        slots: dto.slots,
        servings: dto.servings,
        ingredients: dto.ingredients.map((i) => ({
          foodId: i.food_id,
          grams: i.grams,
        })),
      },
      Number(request.user.id),
    );
  }

  @Post(':id/review')
  @HttpCode(HttpStatus.OK)
  review(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<RecipeView> {
    return this.recipes.review(id, Number(request.user.id), new Date());
  }

  @Post(':id/publish')
  @HttpCode(HttpStatus.OK)
  publish(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<RecipeView> {
    return this.recipes.publish(id, Number(request.user.id), new Date());
  }

  @Post(':id/retire')
  @HttpCode(HttpStatus.OK)
  retire(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() request: { user: JwtPayloadType },
  ): Promise<RecipeView> {
    return this.recipes.retire(id, Number(request.user.id), new Date());
  }
}
