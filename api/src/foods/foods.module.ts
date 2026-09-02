import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FoodsController } from './foods.controller';
import { FoodImagesController } from './food-images.controller';
import { FoodsService } from './foods.service';
import { FoodEntity } from './entities/food.entity';
import { HouseholdMeasureEntity } from './entities/household-measure.entity';

@Module({
  imports: [TypeOrmModule.forFeature([FoodEntity, HouseholdMeasureEntity])],
  controllers: [FoodsController, FoodImagesController],
  providers: [FoodsService],
  exports: [FoodsService],
})
export class FoodsModule {}
