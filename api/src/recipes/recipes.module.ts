import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FoodEntity } from '../foods/entities/food.entity';
import { LogsModule } from '../logs/logs.module';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { AdminRecipesController } from './admin-recipes.controller';
import { RecipeEntity, RecipeIngredientEntity } from './entities/recipe.entity';
import { RecipesController } from './recipes.controller';
import { RecipesService } from './recipes.service';

/// D-263. Imports LogsModule (one-way) so a logged recipe goes through `logFood`.
@Module({
  imports: [
    TypeOrmModule.forFeature([
      RecipeEntity,
      RecipeIngredientEntity,
      FoodEntity,
      ProfileEntity,
    ]),
    LogsModule,
  ],
  controllers: [RecipesController, AdminRecipesController],
  providers: [RecipesService],
})
export class RecipesModule {}
